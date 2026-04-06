import AppKit

let openSettingsNotification = "com.krishnaakhil.pillfloat.openSettings"
let myPID = ProcessInfo.processInfo.processIdentifier

// Check if another instance is already running — match by executable name,
// not bundle ID, because Swift PM binaries in manual .app bundles may not
// report the Info.plist bundle identifier.
let running = NSWorkspace.shared.runningApplications.filter {
    $0.processIdentifier != myPID &&
    ($0.executableURL?.lastPathComponent == "PillFloat" ||
     $0.bundleIdentifier == "com.krishnaakhil.pillfloat")
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
