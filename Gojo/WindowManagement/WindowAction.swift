import Foundation
import KeyboardShortcuts

/// The small v1 set of Rectangle-style actions Gojo exposes as keyboard-first window power.
enum WindowAction: CaseIterable, Equatable, Identifiable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize
    /// Triggers the window's native zoom button (same as double-clicking the title bar) —
    /// toggles between custom size and the app's default zoomed state.
    case zoom

    var id: String { rawName }

    var rawName: String {
        switch self {
        case .leftHalf: return "leftHalf"
        case .rightHalf: return "rightHalf"
        case .topHalf: return "topHalf"
        case .bottomHalf: return "bottomHalf"
        case .maximize: return "maximize"
        case .zoom: return "zoom"
        }
    }

    var label: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .maximize: return "Maximize"
        case .zoom: return "Default Size"
        }
    }

    var shortLabel: String {
        switch self {
        case .leftHalf: return "Left"
        case .rightHalf: return "Right"
        case .topHalf: return "Top"
        case .bottomHalf: return "Bottom"
        case .maximize: return "Max"
        case .zoom: return "Reset"
        }
    }

    var systemImage: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .zoom: return "rectangle.center.inset.filled"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .leftHalf: return "left half"
        case .rightHalf: return "right half"
        case .topHalf: return "top half"
        case .bottomHalf: return "bottom half"
        case .maximize: return "full visible screen"
        case .zoom: return "default size"
        }
    }

    /// True for actions that map to a specific target frame (used by snap geometry).
    /// Zoom is button-press based and has no fixed target frame.
    var isFrameBased: Bool {
        self != .zoom
    }

    /// The user-configurable keyboard shortcut bound to this action.
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .leftHalf: return .windowLeftHalf
        case .rightHalf: return .windowRightHalf
        case .topHalf: return .windowTopHalf
        case .bottomHalf: return .windowBottomHalf
        case .maximize: return .windowMaximize
        case .zoom: return .windowZoom
        }
    }
}
