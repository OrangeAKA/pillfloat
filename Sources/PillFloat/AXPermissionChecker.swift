import AppKit
import ApplicationServices

enum AXPermissionChecker {
    /// Performs a real AX call to verify permission is actually working,
    /// not just reported as granted by the TCC database (which can be stale
    /// after a binary update for unsigned apps).
    ///
    /// Probes by querying Finder's kAXWindowsAttribute (Finder is always
    /// running). Only returns false if the result is .apiDisabled, which
    /// definitively means permission is denied/stale.
    static func isAXActuallyWorking() -> Bool {
        // Find Finder's PID — it's always running
        guard let finder = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder"
        }) else {
            // Finder not running (extremely unlikely) — fall back to trusting TCC
            return AXIsProcessTrustedWithOptions(nil)
        }

        let finderApp = AXUIElementCreateApplication(finder.processIdentifier)
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            finderApp,
            kAXWindowsAttribute as CFString,
            &ref
        )

        // .apiDisabled is the definitive "permission denied" signal.
        // Everything else (.success, .cannotComplete, .noValue, etc.)
        // means AX is functional for this app.
        return result != .apiDisabled
    }
}
