import AppKit

enum PillPreset: String, CaseIterable, Equatable {
    case bottomCenter = "Bottom Center (Default)"
    case topCenter = "Top Center"
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
    case custom = "Custom"

    private static let visiblePillHeight: CGFloat = 70

    func resolve(screenFrame: CGRect, workArea: CGRect, pillSize: CGSize) -> CGPoint {
        let margin: CGFloat = 12
        let invisibleTop = pillSize.height - Self.visiblePillHeight

        switch self {
        case .bottomCenter:
            return CGPoint(
                x: workArea.origin.x + (workArea.width - pillSize.width) / 2,
                y: workArea.origin.y + workArea.height - pillSize.height
            )
        case .topCenter:
            return CGPoint(
                x: workArea.origin.x + (workArea.width - pillSize.width) / 2,
                y: workArea.origin.y + margin - invisibleTop
            )
        case .topLeft:
            return CGPoint(
                x: workArea.origin.x + margin,
                y: workArea.origin.y + margin - invisibleTop
            )
        case .topRight:
            return CGPoint(
                x: workArea.origin.x + workArea.width - pillSize.width - margin,
                y: workArea.origin.y + margin - invisibleTop
            )
        case .bottomLeft:
            return CGPoint(
                x: workArea.origin.x + margin,
                y: workArea.origin.y + workArea.height - pillSize.height - margin
            )
        case .bottomRight:
            return CGPoint(
                x: workArea.origin.x + workArea.width - pillSize.width - margin,
                y: workArea.origin.y + workArea.height - pillSize.height - margin
            )
        case .custom:
            return .zero  // Handled by PositionStore
        }
    }
}

final class PositionStore {
    private let presetKey = "preferredPreset"
    private let absXKey = "customAbsoluteX"
    private let absYKey = "customAbsoluteY"
    private let hasLaunchedKey = "hasLaunchedBefore"

    var preset: PillPreset {
        didSet { UserDefaults.standard.set(preset.rawValue, forKey: presetKey) }
    }

    /// Custom position as absolute CG coordinates (top-left origin).
    var customAbsoluteX: CGFloat {
        didSet { UserDefaults.standard.set(Double(customAbsoluteX), forKey: absXKey) }
    }
    var customAbsoluteY: CGFloat {
        didSet { UserDefaults.standard.set(Double(customAbsoluteY), forKey: absYKey) }
    }

    /// Whether the app has been launched before (for first-launch settings window).
    var hasLaunchedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: hasLaunchedKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasLaunchedKey) }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: presetKey),
           let p = PillPreset(rawValue: raw) {
            preset = p
        } else {
            // Migrate from old "Default" preset or set initial default
            preset = .bottomCenter
        }
        customAbsoluteX = CGFloat(UserDefaults.standard.double(forKey: absXKey))
        customAbsoluteY = CGFloat(UserDefaults.standard.double(forKey: absYKey))
    }

    func resolvePosition(screenFrame: CGRect, workArea: CGRect, pillSize: CGSize) -> CGPoint {
        if preset == .custom {
            return CGPoint(x: customAbsoluteX, y: customAbsoluteY)
        }
        return preset.resolve(screenFrame: screenFrame, workArea: workArea, pillSize: pillSize)
    }
}
