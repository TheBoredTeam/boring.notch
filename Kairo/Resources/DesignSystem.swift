//
//  DesignSystem.swift
//  Kairo — Design System Foundation
//
//  Phase 1 of the redesign. This file defines:
//    1. Color helper (light/dark dynamic resolution on macOS)
//    2. Palette — current "Obsidian" theme (kept default), plus
//       alternates "Aurora" and "Graphite" for evaluation
//    3. Typography scale (SF Pro Display/Text/Mono)
//    4. Spacing scale (4pt grid)
//    5. Radius scale
//    6. Elevation (layered shadow tokens)
//    7. Motion (existing 3 springs + new transition tokens)
//    8. Glass material variants
//    9. Anchor components: KairoGlassPanel, KairoPill, KairoCard
//
//  Backward compatibility: all existing call sites
//  (Kairo.Palette.background, Kairo.Motion.snappy, Kairo.Radius.md, etc.)
//  continue to work. Tokens are now light/dark adaptive — dark mode values
//  are unchanged from before.
//

import AppKit
import SwiftUI

// MARK: - Color helper

extension Color {
    /// Returns a color that resolves differently in light vs dark appearance.
    /// macOS doesn't have iOS's `Color(light:dark:)` initializer, so we build
    /// one through `NSColor`'s dynamic provider.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(NSColor(name: nil) { appearance in
            switch appearance.name {
            case .darkAqua, .vibrantDark,
                 .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
                return NSColor(dark)
            default:
                return NSColor(light)
            }
        })
    }
}

// MARK: - Root namespace

enum Kairo {

    // MARK: - Palette (Obsidian — default, kept current dark values, added light)

    enum Palette {
        // Surfaces
        static let background = Color.adaptive(
            light: Color(red: 0.97, green: 0.97, blue: 0.97),
            dark:  Color(red: 0.039, green: 0.039, blue: 0.039)
        )
        static let surface = Color.adaptive(
            light: Color(red: 1.0, green: 1.0, blue: 1.0),
            dark:  Color(red: 0.063, green: 0.063, blue: 0.063)
        )
        static let surfaceHi = Color.adaptive(
            light: Color(red: 0.95, green: 0.95, blue: 0.96),
            dark:  Color(red: 0.098, green: 0.098, blue: 0.098)
        )

        // Text
        static let text = Color.adaptive(
            light: Color(red: 0.08, green: 0.08, blue: 0.10),
            dark:  Color(red: 0.961, green: 0.961, blue: 0.969)
        )
        static let textDim = Color.adaptive(
            light: Color.black.opacity(0.60),
            dark:  Color.white.opacity(0.60)
        )
        static let textFaint = Color.adaptive(
            light: Color.black.opacity(0.38),
            dark:  Color.white.opacity(0.40)
        )

        // Accents (kept brand-consistent across modes)
        static let accent     = Color(red: 1.0, green: 0.42, blue: 0.10) // Kairo orange
        static let accentSoft = Color(red: 1.0, green: 0.64, blue: 0.40)
        static let orbCore    = Color(red: 0.36, green: 0.55, blue: 1.0) // Kairo blue orb
        static let orbDeep    = Color(red: 0.12, green: 0.23, blue: 0.54)

        // Lines + status
        static let hairline = Color.adaptive(
            light: Color.black.opacity(0.08),
            dark:  Color.white.opacity(0.06)
        )
        static let success = Color(red: 0.20, green: 0.78, blue: 0.35)
        static let danger  = Color(red: 1.0,  green: 0.27, blue: 0.23)

        // Glass tints (subtle — layered on top of system materials)
        static let glassTint = Color.adaptive(
            light: Color.white.opacity(0.40),
            dark:  Color.white.opacity(0.04)
        )
        static let glassStroke = Color.adaptive(
            light: Color.white.opacity(0.80),
            dark:  Color.white.opacity(0.10)
        )
    }

    // MARK: - Alternate palette: Aurora (warm whites, deep teal, gold orb)

    enum PaletteAurora {
        static let background = Color.adaptive(
            light: Color(red: 0.99, green: 0.97, blue: 0.94),
            dark:  Color(red: 0.07,  green: 0.08, blue: 0.10)
        )
        static let surface = Color.adaptive(
            light: Color(red: 1.0,  green: 0.99, blue: 0.97),
            dark:  Color(red: 0.10, green: 0.11, blue: 0.13)
        )
        static let surfaceHi = Color.adaptive(
            light: Color(red: 0.97, green: 0.95, blue: 0.91),
            dark:  Color(red: 0.14, green: 0.15, blue: 0.18)
        )
        static let text = Color.adaptive(
            light: Color(red: 0.13, green: 0.12, blue: 0.10),
            dark:  Color(red: 0.97, green: 0.96, blue: 0.93)
        )
        static let textDim   = Color.adaptive(light: Color.black.opacity(0.62), dark: Color.white.opacity(0.65))
        static let textFaint = Color.adaptive(light: Color.black.opacity(0.40), dark: Color.white.opacity(0.42))

        static let accent     = Color(red: 0.06, green: 0.46, blue: 0.48) // deep teal
        static let accentSoft = Color(red: 0.36, green: 0.72, blue: 0.74)
        static let orbCore    = Color(red: 0.97, green: 0.76, blue: 0.27) // warm gold
        static let orbDeep    = Color(red: 0.54, green: 0.36, blue: 0.10)

        static let hairline = Color.adaptive(light: Color.black.opacity(0.07), dark: Color.white.opacity(0.08))
        static let success  = Color(red: 0.20, green: 0.62, blue: 0.40)
        static let danger   = Color(red: 0.86, green: 0.32, blue: 0.28)
    }

    // MARK: - Alternate palette: Graphite (monochrome + single accent = orb blue)

    enum PaletteGraphite {
        static let background = Color.adaptive(
            light: Color(red: 0.96, green: 0.96, blue: 0.97),
            dark:  Color(red: 0.07, green: 0.07, blue: 0.08)
        )
        static let surface = Color.adaptive(
            light: Color(red: 1.0,  green: 1.0,  blue: 1.0),
            dark:  Color(red: 0.10, green: 0.10, blue: 0.11)
        )
        static let surfaceHi = Color.adaptive(
            light: Color(red: 0.93, green: 0.93, blue: 0.94),
            dark:  Color(red: 0.14, green: 0.14, blue: 0.15)
        )
        static let text = Color.adaptive(
            light: Color(red: 0.08, green: 0.08, blue: 0.10),
            dark:  Color(red: 0.97, green: 0.97, blue: 0.98)
        )
        static let textDim   = Color.adaptive(light: Color.black.opacity(0.58), dark: Color.white.opacity(0.58))
        static let textFaint = Color.adaptive(light: Color.black.opacity(0.36), dark: Color.white.opacity(0.36))

        // Single accent = orb blue. No orange.
        static let accent     = Color(red: 0.36, green: 0.55, blue: 1.0)
        static let accentSoft = Color(red: 0.60, green: 0.74, blue: 1.0)
        static let orbCore    = Color(red: 0.36, green: 0.55, blue: 1.0)
        static let orbDeep    = Color(red: 0.12, green: 0.23, blue: 0.54)

        static let hairline = Color.adaptive(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.07))
        static let success  = Color(red: 0.22, green: 0.72, blue: 0.42)
        static let danger   = Color(red: 1.0,  green: 0.32, blue: 0.30)
    }

    // MARK: - Typography (SF Pro Display / Text / Mono)
    //
    // Heuristic: Display for ≥20pt, Text below. Mono for numeric / system-y
    // readouts. Line spacing tuned for tight info displays (notch + Orbie).

    enum Typography {
        // Display
        static let display = Font.system(size: 34, weight: .semibold, design: .default)

        // Titles
        static let title       = Font.system(size: 22, weight: .semibold, design: .default)
        static let titleSmall  = Font.system(size: 17, weight: .semibold, design: .default)

        // Body
        static let body         = Font.system(size: 14, weight: .regular,  design: .default)
        static let bodyEmphasis = Font.system(size: 14, weight: .semibold, design: .default)
        static let bodySmall    = Font.system(size: 12, weight: .regular,  design: .default)

        // Caption / label
        static let caption       = Font.system(size: 11, weight: .medium,  design: .default)
        static let captionStrong = Font.system(size: 11, weight: .semibold, design: .default)

        // Mono — time, percentages, IDs, debug
        static let mono       = Font.system(size: 12, weight: .medium,  design: .monospaced)
        static let monoSmall  = Font.system(size: 10, weight: .medium,  design: .monospaced)
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
        static let xxxl: CGFloat = 48
    }

    // MARK: - Radius

    enum Radius {
        static let xs: CGFloat   = 6
        static let sm: CGFloat   = 12
        static let md: CGFloat   = 16
        static let lg: CGFloat   = 24
        static let xl: CGFloat   = 32
        static let pill: CGFloat = 999          // any large value = capsule
        static let notch: CGFloat = 9           // MacBook notch outer corner radius
    }

    // MARK: - Elevation (layered shadows — keep subtle on glass surfaces)

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    enum Elevation {
        /// No shadow. Used for inset / flat surfaces (notch closed state).
        static let flat: [Shadow] = []

        /// Hover lift. Very subtle.
        static let hover: [Shadow] = [
            Shadow(color: .black.opacity(0.08), radius: 8,  x: 0, y: 2),
            Shadow(color: .black.opacity(0.06), radius: 2,  x: 0, y: 1)
        ]

        /// Popover / floating panel (Orbie expanded, Note window).
        static let popover: [Shadow] = [
            Shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12),
            Shadow(color: .black.opacity(0.10), radius: 4,  x: 0, y: 1)
        ]

        /// Modal / hero (Hologram orb during call).
        static let modal: [Shadow] = [
            Shadow(color: .black.opacity(0.28), radius: 48, x: 0, y: 24),
            Shadow(color: .black.opacity(0.14), radius: 8,  x: 0, y: 2)
        ]
    }

    // MARK: - Motion

    enum Motion {
        // Existing (preserved)
        static let spring  = Animation.spring(response: 0.55, dampingFraction: 0.78, blendDuration: 0)
        static let snappy  = Animation.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0)
        static let gentle  = Animation.easeInOut(duration: 0.4)

        // New
        static let instant = Animation.linear(duration: 0.06)             // sub-perception flicker
        static let hover   = Animation.spring(response: 0.22, dampingFraction: 0.86)
        static let morph   = Animation.spring(response: 0.65, dampingFraction: 0.74) // notch expand
        static let glide   = Animation.easeInOut(duration: 0.55)          // longer ambient transitions
    }
}

// MARK: - Glass material variants

/// The 4 system materials, named with intent.
enum KairoGlassVariant: CaseIterable {
    case ultraThin   // most translucent — used over content (e.g. Orbie hover preview)
    case thin        // primary glass — used for floating panels (Orbie, Note)
    case regular     // weighty glass — used for elevated cards
    case thick       // most opaque — used for modal / sheet contexts

    var material: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin:      return .thinMaterial
        case .regular:   return .regularMaterial
        case .thick:     return .thickMaterial
        }
    }

    /// Subtle tint laid on top of the material. Light mode adds white, dark
    /// adds a barely-there warm wash — keeps surfaces from looking sterile.
    var tint: Color {
        Kairo.Palette.glassTint
    }

    /// Edge stroke / hairline used to delineate the surface from its background.
    var stroke: Color {
        Kairo.Palette.glassStroke
    }

    var label: String {
        switch self {
        case .ultraThin: return "ultraThin"
        case .thin:      return "thin"
        case .regular:   return "regular"
        case .thick:     return "thick"
        }
    }
}

// MARK: - Glass view modifier
//
// Two forms:
//   .kairoGlass(.thin)                 // applies to any view
//   KairoGlassPanel(.thin) { ... }     // wraps content

extension View {
    /// Applies a glass material background with consistent hairline stroke and
    /// a subtle tint. Use this on any view that needs to act as a Kairo surface.
    func kairoGlass(
        _ variant: KairoGlassVariant = .thin,
        radius: CGFloat = Kairo.Radius.lg
    ) -> some View {
        modifier(KairoGlassModifier(variant: variant, radius: radius))
    }

    /// Applies a layered shadow stack from `Kairo.Elevation`.
    func kairoElevation(_ shadows: [Kairo.Shadow]) -> some View {
        modifier(KairoElevationModifier(shadows: shadows))
    }
}

private struct KairoGlassModifier: ViewModifier {
    let variant: KairoGlassVariant
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background {
                ZStack {
                    shape.fill(variant.material)
                    shape.fill(variant.tint)
                }
            }
            .overlay {
                shape.strokeBorder(variant.stroke, lineWidth: 0.5)
            }
            .clipShape(shape)
    }
}

private struct KairoElevationModifier: ViewModifier {
    let shadows: [Kairo.Shadow]
    func body(content: Content) -> some View {
        shadows.reduce(AnyView(content)) { acc, shadow in
            AnyView(acc.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y))
        }
    }
}

// MARK: - Anchor component: KairoGlassPanel
//
// Generic glass container. Use as the surface primitive for floating panels.

struct KairoGlassPanel<Content: View>: View {
    let variant: KairoGlassVariant
    let radius: CGFloat
    let elevation: [Kairo.Shadow]
    let content: Content

    init(
        _ variant: KairoGlassVariant = .thin,
        radius: CGFloat = Kairo.Radius.lg,
        elevation: [Kairo.Shadow] = Kairo.Elevation.popover,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.radius = radius
        self.elevation = elevation
        self.content = content()
    }

    var body: some View {
        content
            .kairoGlass(variant, radius: radius)
            .kairoElevation(elevation)
    }
}

// MARK: - Anchor component: KairoPill
//
// Small status indicator with optional leading icon. Used for compact-state
// readouts in the notch and in Orbie's idle hints.

struct KairoPill: View {
    enum Tone { case neutral, accent, success, danger }

    let text: String
    let icon: String?
    let tone: Tone

    init(_ text: String, icon: String? = nil, tone: Tone = .neutral) {
        self.text = text
        self.icon = icon
        self.tone = tone
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return Kairo.Palette.text
        case .accent:  return Kairo.Palette.accent
        case .success: return Kairo.Palette.success
        case .danger:  return Kairo.Palette.danger
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return Kairo.Palette.surfaceHi
        case .accent:  return Kairo.Palette.accent.opacity(0.15)
        case .success: return Kairo.Palette.success.opacity(0.15)
        case .danger:  return Kairo.Palette.danger.opacity(0.15)
        }
    }

    var body: some View {
        HStack(spacing: Kairo.Space.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(Kairo.Typography.captionStrong)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, Kairo.Space.sm)
        .padding(.vertical, Kairo.Space.xxs + 1)
        .background(
            Capsule(style: .continuous).fill(background)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Kairo.Palette.hairline, lineWidth: 0.5)
        )
    }
}

// MARK: - Anchor component: KairoCard
//
// Content card with header + body slots. Used in Orbie expanded views, Note,
// and any place a contained section is needed.

struct KairoCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let trailing: AnyView?
    let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        trailing: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            if title != nil || trailing != nil {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Kairo.Space.xxs) {
                        if let title {
                            Text(title)
                                .font(Kairo.Typography.titleSmall)
                                .foregroundStyle(Kairo.Palette.text)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(Kairo.Typography.bodySmall)
                                .foregroundStyle(Kairo.Palette.textDim)
                        }
                    }
                    Spacer()
                    if let trailing { trailing }
                }
            }
            content
        }
        .padding(Kairo.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kairoGlass(.thin, radius: Kairo.Radius.md)
        .kairoElevation(Kairo.Elevation.hover)
    }
}
