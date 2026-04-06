import AppKit

let bundleID = "com.krishnaakhil.pillfloat"
let openSettingsNotification = "com.krishnaakhil.pillfloat.openSettings"

// Check if another instance is already running
let running = NSWorkspace.shared.runningApplications.filter {
    $0.bundleIdentifier == bundleID && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
}

if !running.isEmpty {
    // Another instance exists — tell it to open settings, then quit
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name(openSettingsNotification),
        object: nil
    )
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()
