import SwiftUI

enum Kairo {
    enum Palette {
        static let background  = Color(red: 0.039, green: 0.039, blue: 0.039)
        static let surface     = Color(red: 0.063, green: 0.063, blue: 0.063)
        static let surfaceHi   = Color(red: 0.098, green: 0.098, blue: 0.098)
        static let text        = Color(red: 0.961, green: 0.961, blue: 0.969)
        static let textDim     = Color.white.opacity(0.6)
        static let textFaint   = Color.white.opacity(0.4)
        static let accent      = Color(red: 1.0, green: 0.42, blue: 0.10)
        static let accentSoft  = Color(red: 1.0, green: 0.64, blue: 0.40)
        static let orbCore     = Color(red: 0.36, green: 0.55, blue: 1.0)
        static let orbDeep     = Color(red: 0.12, green: 0.23, blue: 0.54)
        static let hairline    = Color.white.opacity(0.06)
        static let success     = Color(red: 0.20, green: 0.78, blue: 0.35)
        static let danger      = Color(red: 1.0, green: 0.27, blue: 0.23)
    }

    enum Motion {
        static let spring = Animation.spring(response: 0.55, dampingFraction: 0.78, blendDuration: 0)
        static let snappy = Animation.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0)
        static let gentle = Animation.easeInOut(duration: 0.4)
    }

    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }
}
