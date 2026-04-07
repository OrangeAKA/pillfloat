import AppKit
import ApplicationServices

final class PillWatcher {
    private let store: PositionStore
    private var pollTimer: Timer?
    private var targetPID: pid_t?
    private var appElement: AXUIElement?
    private var axObserver: AXObserver?
    private var statusWindow: AXUIElement?

    // Drag state
    private var isDragging = false
    private var dragOffset: CGPoint = .zero   // offset from mouse to window origin at drag start
    private var dragPosition: CGPoint = .zero // current drag target in CG coords
    private var globalMonitors: [Any] = []

    // Permission state
    private(set) var axWorking = false
    private var permissionTimer: Timer?

    /// Called when a drag completes and a custom position is saved.
    var onDragComplete: (() -> Void)?
    /// Called when AX permission status changes.
    var onPermissionChanged: ((Bool) -> Void)?

    init(store: PositionStore) {
        self.store = store
    }

    // MARK: - Lifecycle

    func start() {
        let ws = NSWorkspace.shared
        let nc = ws.notificationCenter

        nc.addObserver(self, selector: #selector(appLaunched(_:)),
                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appTerminated(_:)),
                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        checkPermissionAndSetup()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        permissionTimer?.invalidate()
        permissionTimer = nil
        teardownObserver()
        stopGlobalMonitor()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Permission Check

    private func checkPermissionAndSetup() {
        let working = AXPermissionChecker.isAXActuallyWorking()
        let wasWorking = axWorking
        axWorking = working

        if working {
            permissionTimer?.invalidate()
            permissionTimer = nil

            if globalMonitors.isEmpty {
                startGlobalMonitor()
            }
            if targetPID == nil {
                if let app = NSWorkspace.shared.runningApplications.first(where: {
                    $0.bundleIdentifier == "com.electron.wispr-flow"
                }) {
                    attach(to: app.processIdentifier)
                }
            }
            if !wasWorking {
                onPermissionChanged?(true)
            }
        } else {
            if permissionTimer == nil {
                permissionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                    self?.checkPermissionAndSetup()
                }
            }
            if wasWorking {
                stopGlobalMonitor()
                detach()
                onPermissionChanged?(false)
            }
        }
    }

    // MARK: - App launch/quit

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.electron.wispr-flow" else { return }
        attach(to: app.processIdentifier)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.electron.wispr-flow" else { return }
        detach()
    }

    // MARK: - Attach / Detach

    private func attach(to pid: pid_t) {
        targetPID = pid
        appElement = AXUIElementCreateApplication(pid)
        setupObserver(pid: pid)
        startPolling()
    }

    private func detach() {
        pollTimer?.invalidate()
        pollTimer = nil
        teardownObserver()
        targetPID = nil
        appElement = nil
        statusWindow = nil
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    private func tick() {
        guard let appEl = appElement else { return }

        if statusWindow == nil {
            statusWindow = findStatusWindow(app: appEl)
            if let win = statusWindow {
                observeWindow(win)
            }
        }

        guard let win = statusWindow else { return }

        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, kAXRoleAttribute as CFString, &roleRef) != .success {
            statusWindow = nil
            return
        }

        repositionIfNeeded(win)
    }

    // MARK: - Find Status Window

    private func findStatusWindow(app: AXUIElement) -> AXUIElement? {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }

        for window in windows {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, title == "Status" {
                return window
            }
        }

        for window in windows {
            var sizeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success {
                var size = CGSize.zero
                AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
                if size.width <= 500 && size.height <= 350 && size.width > 100 {
                    return window
                }
            }
        }

        return nil
    }

    // MARK: - Reposition

    func repositionIfNeeded(_ window: AXUIElement) {
        // Off = let Wispr Flow position the pill natively
        if store.preset.isPassthrough && !isDragging { return }

        // During drag, use the drag position instead of the computed target
        let target: CGPoint
        if isDragging {
            target = dragPosition
        } else {
            guard let screen = ScreenUtility.currentScreen() else { return }
            var sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success else { return }
            var pillSize = CGSize.zero
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &pillSize)

            target = store.resolvePosition(
                screenFrame: screen.frame,
                workArea: screen.workArea,
                pillSize: pillSize
            )
        }

        // Read current position
        var posRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success {
            var current = CGPoint.zero
            AXValueGetValue(posRef as! AXValue, .cgPoint, &current)
            if abs(current.x - target.x) < 2 && abs(current.y - target.y) < 2 {
                return
            }
        }

        var point = target
        if let val = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, val)
        }
    }

    func forceReposition() {
        guard let win = statusWindow else { return }

        // When switching to Off, do a one-time move to bottom-center
        // (Wispr's approximate native position) so the user sees immediate
        // feedback, then stop overriding.
        if store.preset.isPassthrough {
            guard let screen = ScreenUtility.currentScreen() else { return }
            var sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef) == .success else { return }
            var pillSize = CGSize.zero
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &pillSize)

            let target = PillPreset.bottomCenter.resolve(
                screenFrame: screen.frame,
                workArea: screen.workArea,
                pillSize: pillSize
            )
            var point = target
            if let val = AXValueCreate(.cgPoint, &point) {
                AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, val)
            }
            return
        }

        repositionIfNeeded(win)
    }

    // MARK: - Global Mouse Monitor (Drag)

    private func startGlobalMonitor() {
        // Monitor mouseDown to detect clicks on the pill
        let downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseDown(event)
        }
        // Monitor mouseDragged to move the pill
        let dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleMouseDragged(event)
        }
        // Monitor mouseUp to finish the drag
        let upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp(event)
        }

        if let m = downMonitor { globalMonitors.append(m) }
        if let m = dragMonitor { globalMonitors.append(m) }
        if let m = upMonitor { globalMonitors.append(m) }
    }

    private func stopGlobalMonitor() {
        for monitor in globalMonitors {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitors.removeAll()
        isDragging = false
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard let win = statusWindow else { return }

        // Get pill window bounds (CG coordinates)
        guard let winPos = getPosition(of: win), let winSize = getSize(of: win) else { return }

        // Convert mouse location to CG coordinates
        let mouseCG = appKitPointToCG(NSEvent.mouseLocation)

        // Hit test against the visible pill area (bottom ~80px of the window)
        let visibleHeight: CGFloat = 80
        let hitRect = CGRect(
            x: winPos.x,
            y: winPos.y + winSize.height - visibleHeight,
            width: winSize.width,
            height: visibleHeight
        )

        if hitRect.contains(mouseCG) {
            isDragging = true
            dragOffset = CGPoint(x: mouseCG.x - winPos.x, y: mouseCG.y - winPos.y)
            dragPosition = winPos
        }
    }

    private func handleMouseDragged(_ event: NSEvent) {
        guard isDragging, let win = statusWindow else { return }

        let mouseCG = appKitPointToCG(NSEvent.mouseLocation)
        dragPosition = CGPoint(x: mouseCG.x - dragOffset.x, y: mouseCG.y - dragOffset.y)

        // Apply immediately (don't wait for the 150ms timer)
        var point = dragPosition
        if let val = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, val)
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard isDragging else { return }
        isDragging = false

        // Save the final position directly as absolute coordinates
        store.preset = .custom
        store.customAbsoluteX = dragPosition.x
        store.customAbsoluteY = dragPosition.y

        onDragComplete?()
    }

    // MARK: - Coordinate Helpers

    private func appKitPointToCG(_ point: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    private func getSize(of element: AXUIElement) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &ref) == .success else { return nil }
        var size = CGSize.zero
        AXValueGetValue(ref as! AXValue, .cgSize, &size)
        return size
    }

    private func getPosition(of element: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(ref as! AXValue, .cgPoint, &point)
        return point
    }

    // MARK: - AX Observer

    private func setupObserver(pid: pid_t) {
        teardownObserver()

        let cb: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon = refcon else { return }
            let watcher = Unmanaged<PillWatcher>.fromOpaque(refcon).takeUnretainedValue()
            let notif = notification as String
            if notif == kAXWindowMovedNotification as String ||
               notif == kAXWindowResizedNotification as String {
                watcher.repositionIfNeeded(element)
            } else if notif == kAXWindowCreatedNotification as String {
                watcher.statusWindow = nil
                watcher.tick()
            }
        }

        var observer: AXObserver?
        guard AXObserverCreate(pid, cb, &observer) == .success, let obs = observer else { return }
        axObserver = obs

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        if let app = appElement {
            AXObserverAddNotification(obs, app, kAXWindowCreatedNotification as CFString, refcon)
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    private func observeWindow(_ window: AXUIElement) {
        guard let obs = axObserver else { return }
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        AXObserverAddNotification(obs, window, kAXWindowMovedNotification as CFString, refcon)
        AXObserverAddNotification(obs, window, kAXWindowResizedNotification as CFString, refcon)
    }

    private func teardownObserver() {
        if let obs = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        axObserver = nil
    }
}
