import Foundation

enum WindowLayoutPreview: Equatable {
    case neutral
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize
    case zoom
    case error

    init(action: WindowAction) {
        switch action {
        case .leftHalf: self = .leftHalf
        case .rightHalf: self = .rightHalf
        case .topHalf: self = .topHalf
        case .bottomHalf: self = .bottomHalf
        case .maximize: self = .maximize
        case .zoom: self = .zoom
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .neutral: return "No target layout selected"
        case .leftHalf: return "Target layout: left half of the focused window display"
        case .rightHalf: return "Target layout: right half of the focused window display"
        case .topHalf: return "Target layout: top half of the focused window display"
        case .bottomHalf: return "Target layout: bottom half of the focused window display"
        case .maximize: return "Target layout: full visible area of the focused window display"
        case .zoom: return "Target layout: window default size"
        case .error: return "Target layout unavailable"
        }
    }
}
