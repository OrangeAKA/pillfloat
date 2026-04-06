import AppKit
import ServiceManagement

final class SettingsWindow: NSWindow {
    private let store: PositionStore
    private let onPositionChanged: () -> Void
    private var presetButtons: [PillPreset: NSButton] = [:]
    private var mapView: ScreenMapView!
    private var enabledCheckbox: NSButton!
    private var loginCheckbox: NSButton!
    private var autoUpdateCheckbox: NSButton!
    private var statusLabel: NSTextField!
    private var versionLabel: NSTextField!
    private var updateBanner: NSView!
    private var updateTitleLabel: NSTextField!
    private var updateNotesLabel: NSTextField!
    private var updateButton: NSButton!
    private var checkUpdateButton: NSButton!
    private var wisprStatusTimer: Timer?

    init(store: PositionStore, isEnabled: Bool, onPositionChanged: @escaping () -> Void) {
        self.store = store
        self.onPositionChanged = onPositionChanged

        let windowWidth: CGFloat = 380
        let windowHeight: CGFloat = 550
        let frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = "PillFloat"
        self.isReleasedWhenClosed = false
        self.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        let pad: CGFloat = 20
        var y = windowHeight - pad

        // -- Update banner (hidden by default, no space reserved when hidden) --
        updateBanner = NSView(frame: NSRect(x: pad, y: 0, width: windowWidth - pad * 2, height: 70))
        updateBanner.wantsLayer = true
        updateBanner.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        updateBanner.layer?.cornerRadius = 8
        updateBanner.isHidden = true

        updateTitleLabel = makeLabel("Update available", size: 12, weight: .semibold)
        updateTitleLabel.frame = NSRect(x: 10, y: 44, width: 240, height: 18)
        updateBanner.addSubview(updateTitleLabel)

        updateNotesLabel = makeLabel("", size: 11, weight: .regular)
        updateNotesLabel.textColor = .secondaryLabelColor
        updateNotesLabel.frame = NSRect(x: 10, y: 10, width: 240, height: 30)
        updateNotesLabel.maximumNumberOfLines = 2
        updateBanner.addSubview(updateNotesLabel)

        updateButton = NSButton(title: "Download", target: self, action: #selector(openDownload))
        updateButton.bezelStyle = .rounded
        updateButton.frame = NSRect(x: windowWidth - pad * 2 - 90, y: 20, width: 80, height: 30)
        updateBanner.addSubview(updateButton)

        // Only reserve space for banner when visible (positioned later in refreshUpdateUI)
        content.addSubview(updateBanner)

        // -- Section: Presets --
        let presetsLabel = makeLabel("Position Presets", size: 11, weight: .medium)
        presetsLabel.textColor = .secondaryLabelColor
        y -= 16
        presetsLabel.frame = NSRect(x: pad, y: y, width: 200, height: 16)
        content.addSubview(presetsLabel)

        y -= 8
        let buttonW: CGFloat = (windowWidth - pad * 2 - 16) / 3
        let buttonH: CGFloat = 32

        // Default button (full width)
        y -= buttonH + 4
        let defaultBtn = NSButton(title: "Default (Native Position)", target: self, action: #selector(presetClicked(_:)))
        defaultBtn.bezelStyle = .rounded
        defaultBtn.frame = NSRect(x: pad, y: y, width: windowWidth - pad * 2, height: buttonH)
        defaultBtn.tag = PillPreset.allCases.firstIndex(of: .defaultPosition) ?? 0
        if store.preset == .defaultPosition {
            defaultBtn.state = .on
            defaultBtn.contentTintColor = .controlAccentColor
        }
        presetButtons[.defaultPosition] = defaultBtn
        content.addSubview(defaultBtn)

        // Position grid
        let presetRows: [[PillPreset]] = [
            [.topLeft, .topCenter, .topRight],
            [.bottomLeft, .bottomCenter, .bottomRight],
        ]
        for row in presetRows {
            y -= buttonH + 4
            for (col, preset) in row.enumerated() {
                let btn = NSButton(title: preset.rawValue, target: self, action: #selector(presetClicked(_:)))
                btn.bezelStyle = .rounded
                btn.frame = NSRect(x: pad + CGFloat(col) * (buttonW + 8), y: y, width: buttonW, height: buttonH)
                btn.tag = PillPreset.allCases.firstIndex(of: preset) ?? 0
                if preset == store.preset {
                    btn.state = .on
                    btn.contentTintColor = .controlAccentColor
                }
                presetButtons[preset] = btn
                content.addSubview(btn)
            }
        }

        // -- Section: Custom Position --
        y -= 24
        let customLabel = makeLabel("Custom Position", size: 11, weight: .medium)
        customLabel.textColor = .secondaryLabelColor
        y -= 16
        customLabel.frame = NSRect(x: pad, y: y, width: 200, height: 16)
        content.addSubview(customLabel)

        y -= 8
        let mapWidth = windowWidth - pad * 2
        let mapHeight: CGFloat = 140
        y -= mapHeight
        mapView = ScreenMapView(
            frame: NSRect(x: pad, y: y, width: mapWidth, height: mapHeight),
            initialFractionX: 0.5,
            initialFractionY: 0.5
        )
        content.addSubview(mapView)

        y -= 6
        let saveCustomBtn = NSButton(title: "Save Custom Position", target: self, action: #selector(saveCustomPosition))
        saveCustomBtn.bezelStyle = .rounded
        saveCustomBtn.contentTintColor = .controlAccentColor
        saveCustomBtn.keyEquivalent = "\r"
        y -= 30
        saveCustomBtn.frame = NSRect(x: pad, y: y, width: mapWidth, height: 30)
        content.addSubview(saveCustomBtn)

        // -- Section: Settings --
        y -= 24
        let settingsLabel = makeLabel("Settings", size: 11, weight: .medium)
        settingsLabel.textColor = .secondaryLabelColor
        y -= 16
        settingsLabel.frame = NSRect(x: pad, y: y, width: 200, height: 16)
        content.addSubview(settingsLabel)

        y -= 4
        enabledCheckbox = NSButton(checkboxWithTitle: "Enabled", target: self, action: #selector(toggleEnabled(_:)))
        enabledCheckbox.state = isEnabled ? .on : .off
        y -= 22
        enabledCheckbox.frame = NSRect(x: pad, y: y, width: 200, height: 18)
        content.addSubview(enabledCheckbox)

        loginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(toggleLoginItem(_:)))
        loginCheckbox.state = isLoginItemEnabled() ? .on : .off
        y -= 22
        loginCheckbox.frame = NSRect(x: pad, y: y, width: 200, height: 18)
        content.addSubview(loginCheckbox)

        autoUpdateCheckbox = NSButton(checkboxWithTitle: "Check for Updates Automatically", target: self, action: #selector(toggleAutoUpdate(_:)))
        autoUpdateCheckbox.state = UpdateChecker.shared.autoCheckEnabled ? .on : .off
        y -= 22
        autoUpdateCheckbox.frame = NSRect(x: pad, y: y, width: 280, height: 18)
        content.addSubview(autoUpdateCheckbox)

        y -= 8
        checkUpdateButton = NSButton(title: "Check for Updates", target: self, action: #selector(manualCheckUpdate))
        checkUpdateButton.bezelStyle = .rounded
        y -= 28
        checkUpdateButton.frame = NSRect(x: pad, y: y, width: 160, height: 28)
        content.addSubview(checkUpdateButton)

        // -- Footer --
        y -= 20
        statusLabel = makeLabel("Target App: Checking...", size: 11, weight: .regular)
        statusLabel.textColor = .tertiaryLabelColor
        y -= 14
        statusLabel.frame = NSRect(x: pad, y: y, width: 300, height: 14)
        content.addSubview(statusLabel)

        versionLabel = makeLabel("v\(UpdateChecker.shared.currentVersion)", size: 11, weight: .regular)
        versionLabel.textColor = .tertiaryLabelColor
        y -= 16
        versionLabel.frame = NSRect(x: pad, y: y, width: 300, height: 14)
        content.addSubview(versionLabel)

        self.contentView = content

        // Start checking target app status
        updateTargetAppStatus()
        wisprStatusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.updateTargetAppStatus()
        }

        // Check for updates
        refreshUpdateUI()
    }

    deinit {
        wisprStatusTimer?.invalidate()
    }

    // MARK: - Presets

    @objc private func presetClicked(_ sender: NSButton) {
        guard let preset = PillPreset.allCases[safe: sender.tag] else { return }
        store.preset = preset
        highlightActivePreset()
        onPositionChanged()
    }

    private func highlightActivePreset() {
        for (preset, btn) in presetButtons {
            if preset == store.preset {
                btn.state = .on
                btn.contentTintColor = .controlAccentColor
            } else {
                btn.state = .off
                btn.contentTintColor = nil
            }
        }
    }

    // MARK: - Custom Position

    @objc private func saveCustomPosition() {
        guard let screen = ScreenUtility.currentScreen() else { return }
        let workArea = screen.workArea
        // The pill window is ~440x300. Account for window size so it stays on screen.
        let estimatedPillWidth: CGFloat = 440
        let estimatedPillHeight: CGFloat = 300
        let x = workArea.origin.x + mapView.fractionX * (workArea.width - estimatedPillWidth)
        let y = workArea.origin.y + mapView.fractionY * (workArea.height - estimatedPillHeight)
        store.preset = .custom
        store.customAbsoluteX = x
        store.customAbsoluteY = y
        highlightActivePreset()
        onPositionChanged()
    }

    // MARK: - Toggles

    var onEnabledToggled: ((Bool) -> Void)?

    @objc private func toggleEnabled(_ sender: NSButton) {
        onEnabledToggled?(sender.state == .on)
    }

    @objc private func toggleLoginItem(_ sender: NSButton) {
        if sender.state == .on {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
        // Verify actual state
        sender.state = isLoginItemEnabled() ? .on : .off
    }

    private func isLoginItemEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleAutoUpdate(_ sender: NSButton) {
        UpdateChecker.shared.autoCheckEnabled = sender.state == .on
    }

    // MARK: - Updates

    @objc private func manualCheckUpdate() {
        checkUpdateButton.isEnabled = false
        checkUpdateButton.title = "Checking..."
        UpdateChecker.shared.check { [weak self] info in
            self?.checkUpdateButton.isEnabled = true
            self?.checkUpdateButton.title = "Check for Updates"
            self?.refreshUpdateUI()
        }
    }

    @objc private func openDownload() {
        if let url = UpdateChecker.shared.latestUpdate?.downloadURL {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshUpdateUI() {
        if let update = UpdateChecker.shared.latestUpdate {
            updateBanner.isHidden = false
            // Position banner at the top of the content area
            let windowWidth = self.frame.width
            let pad: CGFloat = 20
            let contentHeight = self.contentView?.frame.height ?? 510
            updateBanner.frame = NSRect(x: pad, y: contentHeight - pad - 70, width: windowWidth - pad * 2, height: 70)
            updateTitleLabel.stringValue = "Update available: v\(update.version)"
            let lines = update.releaseNotes.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .prefix(2)
                .joined(separator: "\n")
            updateNotesLabel.stringValue = lines.isEmpty ? "A new version is available." : lines
            versionLabel.stringValue = "v\(UpdateChecker.shared.currentVersion) — Update available"
        } else {
            updateBanner.isHidden = true
            versionLabel.stringValue = "v\(UpdateChecker.shared.currentVersion) — No new updates"
        }
    }

    // MARK: - Target App Status

    private func updateTargetAppStatus() {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.electron.wispr-flow"
        }
        statusLabel.stringValue = running ? "Wispr Flow: Running" : "Wispr Flow: Not detected"
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        return label
    }
}

// Safe array subscript
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Screen Map View (reused from original picker)

final class ScreenMapView: NSView {
    var fractionX: CGFloat
    var fractionY: CGFloat

    private let pillWidth: CGFloat = 60
    private let pillHeight: CGFloat = 10
    private let screenInset: CGFloat = 4
    private let menuBarHeight: CGFloat = 10
    private let cornerRadius: CGFloat = 8
    private var isDragging = false

    init(frame: NSRect, initialFractionX: CGFloat, initialFractionY: CGFloat) {
        self.fractionX = initialFractionX
        self.fractionY = initialFractionY
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
    }

    required init?(coder: NSCoder) { fatalError() }

    private var workRect: NSRect {
        NSRect(
            x: screenInset,
            y: screenInset,
            width: bounds.width - screenInset * 2,
            height: bounds.height - screenInset * 2 - menuBarHeight
        )
    }

    private var pillRect: NSRect {
        let work = workRect
        let x = work.origin.x + fractionX * (work.width - pillWidth)
        let y = work.origin.y + (1.0 - fractionY) * (work.height - pillHeight)
        return NSRect(x: x, y: y, width: pillWidth, height: pillHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let screenPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor(white: 0.15, alpha: 1).setFill()
        screenPath.fill()

        let menuBarRect = NSRect(
            x: screenInset,
            y: bounds.height - screenInset - menuBarHeight,
            width: bounds.width - screenInset * 2,
            height: menuBarHeight
        )
        NSColor(white: 0.22, alpha: 1).setFill()
        NSBezierPath(roundedRect: menuBarRect, xRadius: 3, yRadius: 3).fill()

        // Grid
        let work = workRect
        NSColor(white: 0.2, alpha: 1).setStroke()
        for i in 1..<4 {
            let path = NSBezierPath()
            let gy = work.origin.y + work.height * CGFloat(i) / 4
            path.move(to: NSPoint(x: work.origin.x, y: gy))
            path.line(to: NSPoint(x: work.origin.x + work.width, y: gy))
            path.lineWidth = 0.5
            path.stroke()
        }
        for i in 1..<4 {
            let path = NSBezierPath()
            let gx = work.origin.x + work.width * CGFloat(i) / 4
            path.move(to: NSPoint(x: gx, y: work.origin.y))
            path.line(to: NSPoint(x: gx, y: work.origin.y + work.height))
            path.lineWidth = 0.5
            path.stroke()
        }

        // Pill
        let pill = pillRect
        NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: pill.insetBy(dx: -3, dy: -3),
                     xRadius: (pillHeight + 6) / 2, yRadius: (pillHeight + 6) / 2).fill()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: pill, xRadius: pillHeight / 2, yRadius: pillHeight / 2).fill()
        NSColor.white.withAlphaComponent(0.4).setFill()
        let hl = NSRect(x: pill.origin.x + 2, y: pill.midY, width: pill.width - 4, height: pill.height * 0.4)
        NSBezierPath(roundedRect: hl, xRadius: 2, yRadius: 2).fill()
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if pillRect.insetBy(dx: -15, dy: -15).contains(loc) {
            isDragging = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let work = workRect
        fractionX = max(0, min(1, (loc.x - work.origin.x - pillWidth / 2) / (work.width - pillWidth)))
        fractionY = max(0, min(1, 1.0 - (loc.y - work.origin.y - pillHeight / 2) / (work.height - pillHeight)))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }
}
