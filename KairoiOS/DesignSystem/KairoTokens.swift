//
//  KairoTokens.swift
//  KairoiOS — Design tokens mirrored from the macOS app.
//
//  The macOS Kairo.Palette / Kairo.Typography / Kairo.Space / etc. live
//  in a separate target, so we mirror the essentials here. Keep this file
//  in sync with `Kairo/Resources/DesignSystem.swift` until both targets
//  share a Swift package (a Phase 6 task).
//

import SwiftUI

enum Kairo {

    // MARK: - Palette (matches macOS Obsidian, light/dark adaptive)

    enum Palette {
        static let background = Color(
            uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)
                    : UIColor(red: 0.97,  green: 0.97,  blue: 0.97,  alpha: 1)
            }
        )
        static let surface = Color(
            uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.063, green: 0.063, blue: 0.063, alpha: 1)
                    : UIColor(red: 1.0,   green: 1.0,   blue: 1.0,   alpha: 1)
            }
        )
        static let text = Color(
            uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1)
                    : UIColor(red: 0.08,  green: 0.08,  blue: 0.10,  alpha: 1)
            }
        )
        static let textDim = Color(
            uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor.white.withAlphaComponent(0.60)
                    : UIColor.black.withAlphaComponent(0.60)
            }
        )

        // Accents — fixed across modes (brand identity)
        static let accent  = Color(red: 1.0,  green: 0.42, blue: 0.10)
        static let orbCore = Color(red: 0.36, green: 0.55, blue: 1.0)
        static let orbDeep = Color(red: 0.12, green: 0.23, blue: 0.54)
        static let success = Color(red: 0.20, green: 0.78, blue: 0.35)
        static let danger  = Color(red: 1.0,  green: 0.27, blue: 0.23)
    }

    // MARK: - Typography

    enum Typography {
        static let display       = Font.system(size: 28, weight: .semibold)
        static let title         = Font.system(size: 20, weight: .semibold)
        static let titleSmall    = Font.system(size: 16, weight: .semibold)
        static let body          = Font.system(size: 14, weight: .regular)
        static let bodyEmphasis  = Font.system(size: 14, weight: .semibold)
        static let bodySmall     = Font.system(size: 12, weight: .regular)
        static let caption       = Font.system(size: 11, weight: .medium)
        static let captionStrong = Font.system(size: 11, weight: .semibold)
        static let mono          = Font.system(size: 12, weight: .medium, design: .monospaced)
    }

    // MARK: - Spacing (4pt grid)

    enum Space {
        static let xxs:  CGFloat = 2
        static let xs:   CGFloat = 4
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 12
        static let lg:   CGFloat = 16
        static let xl:   CGFloat = 24
        static let xxl:  CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let xs: CGFloat   = 6
        static let sm: CGFloat   = 12
        static let md: CGFloat   = 16
        static let lg: CGFloat   = 24
    }
}
