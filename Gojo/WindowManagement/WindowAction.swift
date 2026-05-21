import Foundation

/// The small v1 set of Rectangle-style actions Gojo exposes as keyboard-first window power.
enum WindowAction: CaseIterable, Equatable, Identifiable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize

    var id: String { rawName }

    var rawName: String {
        switch self {
        case .leftHalf: return "leftHalf"
        case .rightHalf: return "rightHalf"
        case .topHalf: return "topHalf"
        case .bottomHalf: return "bottomHalf"
        case .maximize: return "maximize"
        }
    }

    var label: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .maximize: return "Maximize"
        }
    }

    var shortLabel: String {
        switch self {
        case .leftHalf: return "Left"
        case .rightHalf: return "Right"
        case .topHalf: return "Top"
        case .bottomHalf: return "Bottom"
        case .maximize: return "Max"
        }
    }

    var systemImage: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .leftHalf: return "left half"
        case .rightHalf: return "right half"
        case .topHalf: return "top half"
        case .bottomHalf: return "bottom half"
        case .maximize: return "full visible screen"
        }
    }
}
