//
//  Showcase.swift
//  Kairo — Design System Showcase (Xcode Previews only)
//
//  Visual reference for every token + anchor component. Open in Xcode
//  Previews to see swatches, type samples, spacing, radius, elevation,
//  glass materials, and anchor components side-by-side across all three
//  candidate palettes (Obsidian / Aurora / Graphite) in light and dark.
//
//  Not used at runtime — only the `#Preview` block compiles in DEBUG.
//

import SwiftUI

// MARK: - A simple "palette resolver" so the Showcase can show alternates
// side-by-side without changing the global palette.

private struct PaletteSnapshot {
    let name: String
    let background: Color
    let surface: Color
    let surfaceHi: Color
    let text: Color
    let textDim: Color
    let textFaint: Color
    let accent: Color
    let accentSoft: Color
    let orbCore: Color
    let orbDeep: Color
    let hairline: Color
    let success: Color
    let danger: Color

    static let obsidian = PaletteSnapshot(
        name: "Obsidian",
        background: Kairo.Palette.background,
        surface:    Kairo.Palette.surface,
        surfaceHi:  Kairo.Palette.surfaceHi,
        text:       Kairo.Palette.text,
        textDim:    Kairo.Palette.textDim,
        textFaint:  Kairo.Palette.textFaint,
        accent:     Kairo.Palette.accent,
        accentSoft: Kairo.Palette.accentSoft,
        orbCore:    Kairo.Palette.orbCore,
        orbDeep:    Kairo.Palette.orbDeep,
        hairline:   Kairo.Palette.hairline,
        success:    Kairo.Palette.success,
        danger:     Kairo.Palette.danger
    )

    static let aurora = PaletteSnapshot(
        name: "Aurora",
        background: Kairo.PaletteAurora.background,
        surface:    Kairo.PaletteAurora.surface,
        surfaceHi:  Kairo.PaletteAurora.surfaceHi,
        text:       Kairo.PaletteAurora.text,
        textDim:    Kairo.PaletteAurora.textDim,
        textFaint:  Kairo.PaletteAurora.textFaint,
        accent:     Kairo.PaletteAurora.accent,
        accentSoft: Kairo.PaletteAurora.accentSoft,
        orbCore:    Kairo.PaletteAurora.orbCore,
        orbDeep:    Kairo.PaletteAurora.orbDeep,
        hairline:   Kairo.PaletteAurora.hairline,
        success:    Kairo.PaletteAurora.success,
        danger:     Kairo.PaletteAurora.danger
    )

    static let graphite = PaletteSnapshot(
        name: "Graphite",
        background: Kairo.PaletteGraphite.background,
        surface:    Kairo.PaletteGraphite.surface,
        surfaceHi:  Kairo.PaletteGraphite.surfaceHi,
        text:       Kairo.PaletteGraphite.text,
        textDim:    Kairo.PaletteGraphite.textDim,
        textFaint:  Kairo.PaletteGraphite.textFaint,
        accent:     Kairo.PaletteGraphite.accent,
        accentSoft: Kairo.PaletteGraphite.accentSoft,
        orbCore:    Kairo.PaletteGraphite.orbCore,
        orbDeep:    Kairo.PaletteGraphite.orbDeep,
        hairline:   Kairo.PaletteGraphite.hairline,
        success:    Kairo.PaletteGraphite.success,
        danger:     Kairo.PaletteGraphite.danger
    )
}

// MARK: - Showcase section primitives

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(Kairo.Typography.captionStrong)
            .tracking(1.2)
            .foregroundStyle(Kairo.Palette.textDim)
            .padding(.bottom, Kairo.Space.xs)
    }
}

private struct Swatch: View {
    let color: Color
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.xs) {
            RoundedRectangle(cornerRadius: Kairo.Radius.sm, style: .continuous)
                .fill(color)
                .frame(width: 64, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: Kairo.Radius.sm, style: .continuous)
                        .strokeBorder(Kairo.Palette.hairline, lineWidth: 0.5)
                )
            Text(label)
                .font(Kairo.Typography.monoSmall)
                .foregroundStyle(Kairo.Palette.textDim)
        }
    }
}

private struct PaletteColumn: View {
    let palette: PaletteSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.sm) {
            Text(palette.name)
                .font(Kairo.Typography.titleSmall)
                .foregroundStyle(Kairo.Palette.text)
                .padding(.bottom, Kairo.Space.xs)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72), spacing: Kairo.Space.sm)],
                spacing: Kairo.Space.md
            ) {
                Swatch(color: palette.background, label: "background")
                Swatch(color: palette.surface,    label: "surface")
                Swatch(color: palette.surfaceHi,  label: "surfaceHi")
                Swatch(color: palette.text,       label: "text")
                Swatch(color: palette.textDim,    label: "textDim")
                Swatch(color: palette.textFaint,  label: "textFaint")
                Swatch(color: palette.accent,     label: "accent")
                Swatch(color: palette.accentSoft, label: "accentSoft")
                Swatch(color: palette.orbCore,    label: "orbCore")
                Swatch(color: palette.orbDeep,    label: "orbDeep")
                Swatch(color: palette.hairline,   label: "hairline")
                Swatch(color: palette.success,    label: "success")
                Swatch(color: palette.danger,     label: "danger")
            }
        }
    }
}

// MARK: - Showcase root

struct DesignSystemShowcase: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kairo.Space.xxl) {
                title

                // 1. Palettes
                palettes

                // 2. Typography
                typography

                // 3. Spacing
                spacing

                // 4. Radius
                radius

                // 5. Elevation
                elevation

                // 6. Glass materials
                glass

                // 7. Anchor components
                components
            }
            .padding(Kairo.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Kairo.Palette.background)
        .foregroundStyle(Kairo.Palette.text)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.xs) {
            Text("Kairo Design System")
                .font(Kairo.Typography.display)
            Text("Phase 1 foundation · tokens, glass, anchor components")
                .font(Kairo.Typography.body)
                .foregroundStyle(Kairo.Palette.textDim)
        }
    }

    // MARK: 1. Palettes

    private var palettes: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            SectionHeader(title: "Palettes (current + 2 alternates)")
            HStack(alignment: .top, spacing: Kairo.Space.xl) {
                PaletteColumn(palette: .obsidian)
                PaletteColumn(palette: .aurora)
                PaletteColumn(palette: .graphite)
            }
        }
    }

    // MARK: 2. Typography

    private var typography: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            SectionHeader(title: "Typography")
            VStack(alignment: .leading, spacing: Kairo.Space.sm) {
                typeRow("display",       sample: "Good evening, John.",       font: Kairo.Typography.display)
                typeRow("title",         sample: "Now playing",                font: Kairo.Typography.title)
                typeRow("titleSmall",    sample: "Weather in Kampala",         font: Kairo.Typography.titleSmall)
                typeRow("body",          sample: "Partly cloudy, 24°C. Rain later this afternoon.",
                                                                                 font: Kairo.Typography.body)
                typeRow("bodyEmphasis",  sample: "Tap to expand.",              font: Kairo.Typography.bodyEmphasis)
                typeRow("bodySmall",     sample: "From the morning briefing.", font: Kairo.Typography.bodySmall)
                typeRow("caption",       sample: "5 MIN AGO",                   font: Kairo.Typography.caption)
                typeRow("captionStrong", sample: "LIVE",                        font: Kairo.Typography.captionStrong)
                typeRow("mono",          sample: "14:32:07 · 142 BPM",          font: Kairo.Typography.mono)
                typeRow("monoSmall",     sample: "00:00:42",                    font: Kairo.Typography.monoSmall)
            }
        }
    }

    @ViewBuilder
    private func typeRow(_ name: String, sample: String, font: Font) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Kairo.Space.lg) {
            Text(name)
                .font(Kairo.Typography.monoSmall)
                .foregroundStyle(Kairo.Palette.textFaint)
                .frame(width: 110, alignment: .trailing)
            Text(sample).font(font)
            Spacer()
        }
    }

    // MARK: 3. Spacing

    private var spacing: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            SectionHeader(title: "Spacing (4pt grid)")
            VStack(alignment: .leading, spacing: Kairo.Space.sm) {
                spacingRow("xxs",  value: Kairo.Space.xxs)
                spacingRow("xs",   value: Kairo.Space.xs)
                spacingRow("sm",   value: Kairo.Space.sm)
                spacingRow("md",   value: Kairo.Space.md)
                spacingRow("lg",   value: Kairo.Space.lg)
                spacingRow("xl",   value: Kairo.Space.xl)
                spacingRow("xxl",  value: Kairo.Space.xxl)
                spacingRow("xxxl", value: Kairo.Space.xxxl)
            }
        }
    }

    private func spacingRow(_ name: String, value: CGFloat) -> some View {
        HStack(spacing: Kairo.Space.lg) {
            Text(name).font(Kairo.Typography.mono).frame(width: 60, alignment: .trailing)
                .foregroundStyle(Kairo.Palette.textDim)
            Text("\(Int(value))pt").font(Kairo.Typography.monoSmall)
                .foregroundStyle(Kairo.Palette.textFaint).frame(width: 40, alignment: .trailing)
            Rectangle()
                .fill(Kairo.Palette.accent)
                .frame(width: value, height: 16)
            Spacer()
        }
    }

    // MARK: 4. Radius

    private var radius: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            SectionHeader(title: "Radius")
            HStack(alignment: .bottom, spacing: Kairo.Space.lg) {
                radiusTile("xs",    Kairo.Radius.xs)
                radiusTile("sm",    Kairo.Radius.sm)
                radiusTile("md",    Kairo.Radius.md)
                radiusTile("lg",    Kairo.Radius.lg)
                radiusTile("xl",    Kairo.Radius.xl)
                radiusTile("pill",  Kairo.Radius.pill)
                radiusTile("notch", Kairo.Radius.notch)
            }
        }
    }

    private func radiusTile(_ name: String, _ value: CGFloat) -> some View {
        VStack(spacing: Kairo.Space.xs) {
            RoundedRectangle(cornerRadius: min(value, 40), style: .continuous)
                .fill(Kairo.Palette.surfaceHi)
                .frame(width: 80, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: min(value, 40), style: .continuous)
                        .strokeBorder(Kairo.Palette.hairline, lineWidth: 0.5)
                )
            Text(name).font(Kairo.Typography.monoSmall).foregroundStyle(Kairo.Palette.textDim)
        }
    }

    // MARK: 5. Elevation

    private var elevation: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            SectionHeader(title: "Elevation")
            HStack(spacing: Kairo.Space.xl) {
                elevationTile("flat",    Kairo.Elevation.flat)
                elevationTile("hover",   Kairo.Elevation.hover)
                elevationTile("popover", Kairo.Elevation.popover)
                elevationTile("modal",   Kairo.Elevation.modal)
            }
            .padding(.vertical, Kairo.Space.xl)
        }
    }

    private func elevationTile(_ name: String, _ shadows: [Kairo.Shadow]) -> some View {
        VStack(spacing: Kairo.Space.sm) {
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .fill(Kairo.Palette.surface)
                .frame(width: 110, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                        .strokeBorder(Kairo.Palette.hairline, lineWidth: 0.5)
                )
                .kairoElevation(shadows)
            Text(name).font(Kairo.Typography.monoSmall).foregroundStyle(Kairo.Palette.textDim)
        }
    }

    // MARK: 6. Glass materials

    private var glass: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            SectionHeader(title: "Glass materials")
            // Use a busy backdrop so the material translucency is visible.
            ZStack {
                LinearGradient(
                    colors: [Kairo.Palette.orbCore, Kairo.Palette.accent, Kairo.Palette.orbDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                HStack(spacing: Kairo.Space.lg) {
                    ForEach(KairoGlassVariant.allCases, id: \.label) { variant in
                        VStack(spacing: Kairo.Space.sm) {
                            Text(variant.label).font(Kairo.Typography.bodyEmphasis)
                            Text("glass surface").font(Kairo.Typography.bodySmall)
                                .foregroundStyle(Kairo.Palette.textDim)
                        }
                        .padding(Kairo.Space.lg)
                        .frame(width: 140, height: 100)
                        .kairoGlass(variant, radius: Kairo.Radius.md)
                    }
                }
                .padding(Kairo.Space.xl)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: Kairo.Radius.lg, style: .continuous))
        }
    }

    // MARK: 7. Anchor components

    private var components: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            SectionHeader(title: "Anchor components")

            // Pills
            HStack(spacing: Kairo.Space.sm) {
                KairoPill("LIVE",       icon: "dot.radiowaves.left.and.right", tone: .accent)
                KairoPill("Connected",  icon: "checkmark.circle.fill",         tone: .success)
                KairoPill("3 unread",   icon: "bell.fill",                     tone: .neutral)
                KairoPill("Offline",    icon: "wifi.slash",                    tone: .danger)
                KairoPill("24°C")
            }

            // Cards
            HStack(alignment: .top, spacing: Kairo.Space.lg) {
                KairoCard(title: "Now playing", subtitle: "Kendrick Lamar — HUMBLE.") {
                    HStack {
                        Image(systemName: "music.note")
                            .font(.system(size: 28))
                            .foregroundStyle(Kairo.Palette.accent)
                        VStack(alignment: .leading) {
                            Text("DAMN.").font(Kairo.Typography.body)
                            Text("01:42 / 02:57").font(Kairo.Typography.mono)
                                .foregroundStyle(Kairo.Palette.textDim)
                        }
                        Spacer()
                    }
                }

                KairoCard(
                    title: "Weather",
                    subtitle: "Kampala",
                    trailing: AnyView(KairoPill("Now", tone: .accent))
                ) {
                    HStack(spacing: Kairo.Space.lg) {
                        Image(systemName: "cloud.sun.fill")
                            .font(.system(size: 36))
                            .symbolRenderingMode(.multicolor)
                        VStack(alignment: .leading) {
                            Text("24°C").font(Kairo.Typography.title)
                            Text("Partly cloudy")
                                .font(Kairo.Typography.bodySmall)
                                .foregroundStyle(Kairo.Palette.textDim)
                        }
                        Spacer()
                    }
                }
            }

            // GlassPanel sample
            KairoGlassPanel(.regular, radius: Kairo.Radius.lg) {
                VStack(alignment: .leading, spacing: Kairo.Space.sm) {
                    Text("KairoGlassPanel").font(Kairo.Typography.titleSmall)
                    Text("Generic glass surface primitive. Use for floating panels, "
                       + "Orbie expanded states, and any container that should read as a "
                       + "Kairo surface.")
                        .font(Kairo.Typography.body)
                        .foregroundStyle(Kairo.Palette.textDim)
                }
                .padding(Kairo.Space.lg)
            }
            .frame(maxWidth: 520)
            .padding(.top, Kairo.Space.lg)
        }
    }
}

// MARK: - Previews

#Preview("Design System · Dark") {
    DesignSystemShowcase()
        .frame(width: 1200, height: 1800)
        .preferredColorScheme(.dark)
}

#Preview("Design System · Light") {
    DesignSystemShowcase()
        .frame(width: 1200, height: 1800)
        .preferredColorScheme(.light)
}
