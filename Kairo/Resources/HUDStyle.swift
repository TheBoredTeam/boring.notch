//
//  HUDStyle.swift
//  Kairo — Jarvis / Iron Man HUD styling layer
//
//  Sits *on top of* DesignSystem.swift, not in place of it. Tokens
//  (typography, space, radius) still come from `Kairo.*`; this file
//  adds the heads-up-display character — corner brackets, scan lines,
//  grid backgrounds, animated rim glow, sweeping highlight — and
//  the specific HUD components used by the notch idle screen.
//
//  HUD palette is a thin slice over Kairo.Palette:
//    primary  = cyan       (K.cyan       — already brand)
//    alert    = warm red   (K.red)
//    accent2  = magenta    (K.pink)
//    dim      = cyan dim   (K.cyan @ 30%)
//    rule     = white @ 8%
//

import SwiftUI

enum HUDPalette {
    static let primary = K.cyan
    static let alert   = K.red
    static let accent2 = K.pink
    static let dim     = K.cyan.opacity(0.30)
    static let rule    = Color.white.opacity(0.08)
}

// MARK: - 1. Corner brackets
//
// Four L-shapes drawn at the four corners of a rect. Used to wrap a card
// or readout in the classic "HUD targeting box" look.

struct HUDBrackets: View {
    var color: Color = HUDPalette.primary
    var thickness: CGFloat = 1
    var length: CGFloat = 12
    var inset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // top-left
                cornerL(rotation: 0,      x: inset,          y: inset)
                // top-right
                cornerL(rotation: 90,     x: w - inset,      y: inset)
                // bottom-right
                cornerL(rotation: 180,    x: w - inset,      y: h - inset)
                // bottom-left
                cornerL(rotation: 270,    x: inset,          y: h - inset)
            }
        }
        .allowsHitTesting(false)
    }

    private func cornerL(rotation: Double, x: CGFloat, y: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: length))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: length, y: 0))
        }
        .stroke(color, lineWidth: thickness)
        .rotationEffect(.degrees(rotation), anchor: .topLeading)
        .frame(width: length, height: length)
        .position(x: x, y: y)
    }
}

// MARK: - 2. Scan lines

struct HUDScanLines: View {
    var spacing: CGFloat = 3
    var opacity: Double = 0.04
    var sweepOpacity: Double = 0.08
    var sweepPeriod: Double = 4.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let sweep = (t.truncatingRemainder(dividingBy: sweepPeriod)) / sweepPeriod

            GeometryReader { geo in
                ZStack {
                    // static horizontal lines via Canvas (fast)
                    Canvas { ctx, size in
                        for y in stride(from: 0, to: size.height, by: spacing) {
                            ctx.fill(
                                Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                                with: .color(.white.opacity(opacity))
                            )
                        }
                    }
                    // sweeping cyan highlight band
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [
                                .clear,
                                HUDPalette.primary.opacity(sweepOpacity),
                                HUDPalette.primary.opacity(sweepOpacity * 1.8),
                                HUDPalette.primary.opacity(sweepOpacity),
                                .clear
                            ],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(height: 48)
                        .offset(y: -geo.size.height / 2 + CGFloat(sweep) * (geo.size.height + 48))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 3. Subtle grid

struct HUDGrid: View {
    var spacing: CGFloat = 16
    var opacity: Double = 0.05

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                for x in stride(from: 0, to: size.width, by: spacing) {
                    ctx.fill(
                        Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)),
                        with: .color(HUDPalette.primary.opacity(opacity))
                    )
                }
                for y in stride(from: 0, to: size.height, by: spacing) {
                    ctx.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)),
                        with: .color(HUDPalette.primary.opacity(opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 4. Animated rim glow (sweeping gradient stroke)

struct HUDRimGlow: ViewModifier {
    var color: Color = HUDPalette.primary
    var thickness: CGFloat = 1
    var radius: CGFloat = Kairo.Radius.sm
    var period: Double = 5.0

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.overlay {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let angle = ((t.truncatingRemainder(dividingBy: period)) / period) * 360
                shape.strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: color.opacity(0.10), location: 0.00),
                            .init(color: color.opacity(0.60), location: 0.45),
                            .init(color: color.opacity(0.95), location: 0.50),
                            .init(color: color.opacity(0.60), location: 0.55),
                            .init(color: color.opacity(0.10), location: 1.00)
                        ]),
                        center: .center,
                        angle: .degrees(angle)
                    ),
                    lineWidth: thickness
                )
            }
        }
    }
}

// MARK: - 5. HUD glow (drop-shadow halo)

extension View {
    /// Adds a cyan / accent halo behind a view. Use sparingly — strong
    /// shadows on every surface kill performance.
    func hudGlow(_ color: Color = HUDPalette.primary, radius: CGFloat = 12, opacity: Double = 0.45) -> some View {
        self.shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 0)
    }

    /// Wraps a view in HUD chrome:
    ///   - dark glass base
    ///   - subtle grid background
    ///   - scan lines
    ///   - animated rim glow
    ///   - corner brackets
    /// All optional via the flags.
    func hudPanel(
        radius: CGFloat = Kairo.Radius.sm,
        rim: Bool = true,
        scanLines: Bool = true,
        grid: Bool = true,
        brackets: Bool = true,
        tint: Color = HUDPalette.primary
    ) -> some View {
        modifier(HUDPanelModifier(
            radius: radius, rim: rim, scanLines: scanLines, grid: grid, brackets: brackets, tint: tint
        ))
    }

    /// Animated rim glow only (no other chrome).
    func hudRim(_ color: Color = HUDPalette.primary, thickness: CGFloat = 1, radius: CGFloat = Kairo.Radius.sm) -> some View {
        modifier(HUDRimGlow(color: color, thickness: thickness, radius: radius))
    }
}

private struct HUDPanelModifier: ViewModifier {
    let radius: CGFloat
    let rim: Bool
    let scanLines: Bool
    let grid: Bool
    let brackets: Bool
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    // Deep dark base — HUD wants near-pure black to make cyan pop
                    shape.fill(Color.black.opacity(0.55))
                    shape.fill(.ultraThinMaterial)
                    if grid {
                        HUDGrid(spacing: 18, opacity: 0.04)
                            .clipShape(shape)
                    }
                    if scanLines {
                        HUDScanLines(spacing: 3, opacity: 0.025, sweepOpacity: 0.05)
                            .clipShape(shape)
                    }
                }
            }
            .overlay {
                if rim {
                    Color.clear
                        .modifier(HUDRimGlow(color: tint, thickness: 0.8, radius: radius))
                } else {
                    shape.strokeBorder(tint.opacity(0.25), lineWidth: 0.5)
                }
            }
            .overlay {
                if brackets {
                    HUDBrackets(color: tint, thickness: 1, length: 10, inset: 4)
                }
            }
    }
}

// MARK: - 6. HUD components used by the notch idle screen

/// A small status chip in the upper corner of an HUD panel —
/// `[ TITLE · 0xAB12 ]` style. Used as the card heading.
struct HUDLabel: View {
    let text: String
    var trailing: String? = nil
    var color: Color = HUDPalette.primary

    var body: some View {
        HStack(spacing: Kairo.Space.xs) {
            Text("◆")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(color.opacity(0.9))
            Text(text.uppercased())
                .font(Kairo.Typography.captionStrong.monospaced())
                .tracking(1.6)
                .foregroundStyle(color.opacity(0.85))
            if let trailing {
                Text("·").foregroundStyle(color.opacity(0.4))
                    .font(Kairo.Typography.monoSmall)
                Text(trailing)
                    .font(Kairo.Typography.monoSmall)
                    .foregroundStyle(color.opacity(0.55))
            }
        }
    }
}

/// HUD-style readout: big mono number with a unit and an optional
/// caption underneath. Used inside an HUD panel as the primary data point.
struct HUDReadout: View {
    let value: String
    var unit: String? = nil
    var caption: String? = nil
    var tint: Color = HUDPalette.primary

    var body: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.xxs) {
            HStack(alignment: .lastTextBaseline, spacing: Kairo.Space.xs) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.kTextPrimary)
                    .shadow(color: tint.opacity(0.4), radius: 4)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tint.opacity(0.7))
                }
            }
            if let caption {
                Text(caption.uppercased())
                    .font(Kairo.Typography.monoSmall)
                    .tracking(0.8)
                    .foregroundStyle(Color.kTextTertiary)
            }
        }
    }
}

/// HUD-style status indicator dot — pulsing colored circle with a
/// monospace label. Used in the bottom system bar of the notch idle screen.
struct HUDStatusDot: View {
    let label: String
    let color: Color
    let active: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = active ? 0.5 + 0.5 * abs(sin(t * 2)) : 0.3
            HStack(spacing: Kairo.Space.xs + 1) {
                Circle()
                    .fill(color.opacity(pulse))
                    .frame(width: 6, height: 6)
                    .shadow(color: color.opacity(active ? 0.7 : 0), radius: 4)
                Text(label.uppercased())
                    .font(Kairo.Typography.monoSmall)
                    .tracking(1.2)
                    .foregroundStyle(color.opacity(active ? 0.85 : 0.45))
            }
        }
    }
}
