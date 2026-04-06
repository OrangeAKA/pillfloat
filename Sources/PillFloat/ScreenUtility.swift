import AppKit

/// Utilities for working with screen coordinates.
/// macOS has two coordinate systems:
///   - AppKit: origin at bottom-left of primary screen
///   - CG/AX: origin at top-left of primary screen
/// The Accessibility API uses CG coordinates.
enum ScreenUtility {

    /// Convert an AppKit NSScreen frame to CG coordinates (top-left origin).
    static func cgRect(from appKitRect: NSRect) -> CGRect {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else {
            return appKitRect
        }
        return CGRect(
            x: appKitRect.origin.x,
            y: primaryHeight - appKitRect.origin.y - appKitRect.height,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    /// Get the screen containing the mouse cursor, with frames in CG coordinates.
    static func currentScreen() -> (frame: CGRect, workArea: CGRect)? {
        let mouseLocation = NSEvent.mouseLocation  // AppKit coordinates
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? NSScreen.main else {
            return nil
        }
        return (
            frame: cgRect(from: screen.frame),
            workArea: cgRect(from: screen.visibleFrame)
        )
    }
}
