import SwiftUI

enum OrbieSize: Equatable {
    case orb, pill, card, panel, canvas, fullscreen

    var dimensions: CGSize {
        switch self {
        case .orb:        return CGSize(width: 72,   height: 72)
        case .pill:       return CGSize(width: 320,  height: 88)
        case .card:       return CGSize(width: 720,  height: 360)
        case .panel:      return CGSize(width: 900,  height: 560)
        case .canvas:     return CGSize(width: 1200, height: 760)
        case .fullscreen: return CGSize(width: -1,   height: -1)
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .orb:        return 36
        case .pill:       return 44
        case .card, .panel, .canvas: return 32
        case .fullscreen: return 0
        }
    }
}
