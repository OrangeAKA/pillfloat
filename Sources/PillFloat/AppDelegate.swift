import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let store = PositionStore()
    private var watcher: PillWatcher!
    private var enabled = true
    private var presetMenuItems: [NSMenuItem] = []
    private var customMenuItem: NSMenuItem!
    private var updateMenuItem: NSMenuItem!
    private var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check accessibility
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
        if !trusted {
            print("Accessibility permission required. Grant access in System Settings → Privacy & Security → Accessibility.")
        }

        // Listen for "open settings" from a second instance launched via Spotlight
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openSettingsAction),
            name: NSNotification.Name("com.krishnaakhil.pillfloat.openSettings"),
            object: nil
        )

        // Menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pill.circle", accessibilityDescription: "PillFloat")
                ?? makeTextImage("P")
            button.image?.isTemplate = true
        }

        buildMenu()

        // Start watcher
        watcher = PillWatcher(store: store)
        watcher.onDragComplete = { [weak self] in
            self?.updateCheckmarks()
            self?.settingsWindow?.refreshUpdateUI()
        }
        watcher.start()

        // Check for updates
        UpdateChecker.shared.checkIfNeeded { [weak self] _ in
            self?.refreshUpdateMenuItem()
        }

        // Show settings window on first launch
        if !store.hasLaunchedBefore {
            store.hasLaunchedBefore = true
            openSettings()
        }
    }

    /// Called when the user relaunches the app from Spotlight/Finder while it's already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        // Update item (hidden by default)
        updateMenuItem = NSMenuItem(title: "Update Available", action: #selector(openUpdatePage), keyEquivalent: "")
        updateMenuItem.target = self
        updateMenuItem.isHidden = true
        menu.addItem(updateMenuItem)

        let headerItem = NSMenuItem(title: "Pill Position", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        for preset in PillPreset.allCases where preset != .custom {
            let item = NSMenuItem(title: preset.rawValue, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            if preset == store.preset {
                item.state = .on
            }
            presetMenuItems.append(item)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        customMenuItem = NSMenuItem(title: "Custom (Drag or use Settings)", action: nil, keyEquivalent: "")
        customMenuItem.isEnabled = false
        if store.preset == .custom {
            customMenuItem.state = .on
        }
        menu.addItem(customMenuItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let enableItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        enableItem.target = self
        enableItem.state = .on
        menu.addItem(enableItem)

        menu.addItem(.separator())

        let uninstallItem = NSMenuItem(title: "Uninstall PillFloat...", action: #selector(uninstall(_:)), keyEquivalent: "")
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateCheckmarks() {
        for item in presetMenuItems {
            item.state = (item.representedObject as? PillPreset) == store.preset ? .on : .off
        }
        customMenuItem.state = store.preset == .custom ? .on : .off
    }

    private func refreshUpdateMenuItem() {
        if let update = UpdateChecker.shared.latestUpdate {
            updateMenuItem.title = "⬆ Update Available (v\(update.version))"
            updateMenuItem.isHidden = false
        } else {
            updateMenuItem.isHidden = true
        }
    }

    // MARK: - Actions

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? PillPreset else { return }
        store.preset = preset
        updateCheckmarks()
        watcher.forceReposition()
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    private func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = SettingsWindow(store: store, isEnabled: enabled) { [weak self] in
            self?.updateCheckmarks()
            self?.watcher.forceReposition()
            self?.refreshUpdateMenuItem()
        }
        window.onEnabledToggled = { [weak self] isOn in
            self?.setEnabled(isOn)
        }
        window.onUninstall = { [weak self] in
            self?.performUninstall()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func openUpdatePage() {
        if let url = UpdateChecker.shared.latestUpdate?.downloadURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        let newState = sender.state != .on
        sender.state = newState ? .on : .off
        setEnabled(newState)
    }

    private func setEnabled(_ isOn: Bool) {
        enabled = isOn
        if enabled {
            watcher.start()
        } else {
            watcher.stop()
        }
    }

    @objc private func uninstall(_ sender: NSMenuItem) {
        performUninstall()
    }

    private func performUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall PillFloat?"
        alert.informativeText = "This will remove PillFloat from your Applications folder, disable Launch at Login, and clear all settings."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        // 1. Disable login item
        try? SMAppService.mainApp.unregister()

        // 2. Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // Also clear by known keys in case bundle ID isn't set
        for key in ["preferredPreset", "customAbsoluteX", "customAbsoluteY",
                     "hasLaunchedBefore", "lastUpdateCheckDate", "autoCheckForUpdates"] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // 3. Move .app to Trash
        let appURL = Bundle.main.bundleURL
        if appURL.path.contains("/Applications/") {
            NSWorkspace.shared.recycle([appURL]) { _, error in
                if error != nil {
                    // Fallback: remove with a shell script after quit
                    let script = "sleep 1 && rm -rf '\(appURL.path)'"
                    Process.launchedProcess(launchPath: "/bin/bash", arguments: ["-c", script])
                }
            }
        }

        // 4. Stop and quit
        watcher.stop()
        NSApplication.shared.terminate(nil)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        watcher.stop()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func makeTextImage(_ text: String) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18))
        img.lockFocus()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.controlTextColor,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(x: (18 - size.width) / 2, y: (18 - size.height) / 2))
        img.unlockFocus()
        return img
    }
}
