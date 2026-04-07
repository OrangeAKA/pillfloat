import ApplicationServices

enum AXPermissionChecker {
    /// Performs a real AX call to verify permission is actually working,
    /// not just reported as granted by the TCC database (which can be stale
    /// after a binary update for unsigned apps).
    static func isAXActuallyWorking() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &ref
        )
        // .success, .noValue, .notImplemented all mean AX is functional
        // .apiDisabled means permission is stale/denied
        switch result {
        case .success, .noValue, .notImplemented, .attributeUnsupported:
            return true
        default:
            return false
        }
    }

    /// Returns true when macOS reports the app as trusted but AX calls
    /// actually fail — indicates a stale TCC entry after binary change.
    static func isTrustedButStale() -> Bool {
        let trusted = AXIsProcessTrustedWithOptions(nil)
        return trusted && !isAXActuallyWorking()
    }
}
