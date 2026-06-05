//
//  PiAuroraView.swift
//  boringNotch
//
//  The palette-driven aurora, recovered (f6f3f31) and relocated from the collapsed peek
//  into the hover-expanded Pi panel. It streams ONLY while the agent runs and ONLY on a
//  surface the user deliberately opened — the collapsed peek stays quiet (unchanged), and
//  the Composio menu-bar app has no aurora. See the surfaces-split-by-frequency decision.
//
//  The geometry-independent palette helpers (companionColor, auroraStops, rawColor,
//  deepen, toolCallActive) are copied verbatim from the original PiPeekView so the brand
//  color logic stays identical; only the gradient body is re-authored for the tall panel
//  (the peek's body was tuned for a 30pt chin with under-notch underglow pools).
//

import AppKit
import SwiftUI

struct PiAuroraView: View {
    @ObservedObject var pi = PiAgentManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Palette helpers (verbatim from f6f3f31 PiPeekView — layout-independent)

    /// The companion hue used to give a *single-color* (or empty) toolkit mark a second
    /// stop, so a mono logo's aurora still has internal depth instead of one flat pool.
    /// A clamped ≤40° analogous shift of the dominant color toward the palette's second
    /// hue — or a synthetic +30° when there's only one hue. Near-gray / empty → indigo.
    private var companionColor: Color {
        let palette = pi.toolkitPalette
        guard let first = palette.first?.usingColorSpace(.sRGB) else {
            return Color(nsColor: .systemIndigo)
        }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        first.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.15 { return Color(nsColor: .systemIndigo) }

        let targetHue: CGFloat
        if palette.count > 1, let second = palette[1].usingColorSpace(.sRGB) {
            var h2: CGFloat = 0, s2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            second.getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2)
            targetHue = h2
        } else {
            targetHue = (h + 30.0 / 360.0).truncatingRemainder(dividingBy: 1.0)
        }

        var delta = targetHue - h
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        let maxShift: CGFloat = 40.0 / 360.0
        let clamped = max(-maxShift, min(maxShift, delta))
        var companionHue = (h + clamped).truncatingRemainder(dividingBy: 1.0)
        if companionHue < 0 { companionHue += 1 }

        return Color(nsColor: NSColor(hue: companionHue, saturation: s, brightness: b, alpha: 1))
    }

    /// The toolkit's brand palette as `(color, weight)` pairs the aurora paints directly,
    /// rather than averaging them into one muddy blob. A single-hue mark is paired with
    /// its `companionColor`; an empty palette falls back to indigo + companion. Capped at
    /// the anchor count. Keyed by `pi.toolkitPaletteIsRaw`: raw curated overrides render
    /// verbatim (weight rides in the source alpha); derived palettes are re-saturated.
    private var auroraStops: [(color: Color, weight: CGFloat)] {
        let raw = pi.toolkitPaletteIsRaw
        let mapped: [(color: Color, weight: CGFloat)] = pi.toolkitPalette.map {
            let w = raw ? ($0.usingColorSpace(.sRGB)?.alphaComponent ?? 1) : 1
            let c = raw ? Self.rawColor($0) : Self.deepen($0)
            return (color: c, weight: w)
        }
        guard let first = mapped.first else {
            return [(color: Self.deepen(.systemIndigo), weight: 1), (color: companionColor, weight: 1)]
        }
        let base = mapped.count >= 2 ? mapped : [first, (color: companionColor, weight: 1)]
        return Array(base.prefix(Self.panelAnchors.count))
    }

    /// A curated stop → SwiftUI `Color`, verbatim — no `deepen` re-saturation. The weight
    /// rides in `ns`'s alpha; we force opacity 1 here and apply the weight as a bloom
    /// multiplier in `aurora` instead.
    private static func rawColor(_ ns: NSColor) -> Color {
        guard let c = ns.usingColorSpace(.sRGB) else { return Color(nsColor: ns) }
        return Color(.sRGB, red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, opacity: 1)
    }

    /// Restore a brand color to a deep, saturated tone for the aurora, undoing the
    /// toward-white wash that `legibleTint` applies for text legibility.
    private static func deepen(_ ns: NSColor) -> Color {
        guard let c = ns.usingColorSpace(.sRGB) else { return Color(nsColor: ns) }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let ds = s < 0.12 ? s : max(s, 0.85)
        let db = min(b, 0.80)
        return Color(nsColor: NSColor(hue: h, saturation: ds, brightness: db, alpha: 1))
    }

    /// True while the model is forming or executing a tool call — drives the bloom's
    /// swell. Plain thinking keeps it dim; tool work makes it bloom.
    private var toolCallActive: Bool {
        pi.isForming || pi.currentTool != nil
    }

    // MARK: - Panel layout

    /// Bloom anchors distributed across the *tall* expanded panel (re-tuned from the
    /// peek's two-under-the-chin pools). Biased toward edges/corners so the brand light
    /// frames the content rather than washing over the text in the middle.
    private static let panelAnchors: [UnitPoint] = [
        .init(x: 0.14, y: 0.16),   // top-left
        .init(x: 0.86, y: 0.26),   // upper-right
        .init(x: 0.18, y: 0.84),   // lower-left
        .init(x: 0.84, y: 0.90),   // bottom-right
        .init(x: 0.50, y: 0.52),   // center, deep — only used by 5-stop palettes
    ]

    // MARK: - Body

    var body: some View {
        aurora
    }

    /// One additive radial bloom per brand color, distributed across the panel. Painted
    /// over an explicit black base with `.screen` (additive light) inside a
    /// `compositingGroup` so deep saturated color lands where each anchor sits and true
    /// black sits between — the mockup's "dark, strong color" look, not a pastel wash.
    /// The black base matches the notch's own background, so at rest (opacity 0) the panel
    /// reads exactly as before. Fades up while running, swells on tool calls, gone at rest.
    private var aurora: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let radius = max(w, h) * 0.55
            let stops = auroraStops
            ZStack {
                Color.black
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    let anchor = Self.panelAnchors[index % Self.panelAnchors.count]
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: stop.color.opacity(0.55 * stop.weight), location: 0),
                            .init(color: stop.color.opacity(0), location: 0.72),
                        ]),
                        center: anchor,
                        startRadius: 0,
                        endRadius: radius
                    )
                    .blendMode(.screen)
                }
            }
            .frame(width: w, height: h)
        }
        .compositingGroup()
        .blur(radius: 6)
        // Swell on tool work (mirrors the peek's bloom), uniform from center on the panel.
        .scaleEffect(toolCallActive ? 1.0 : 0.98)
        // Gate exactly as the peek did: invisible at rest, dim while thinking, full on tools.
        .opacity(pi.isRunning ? (toolCallActive ? 1.0 : 0.78) : 0)
        .animation(reduceMotion ? Motion.reduced : Motion.glowBloom, value: pi.isRunning)
        .animation(reduceMotion ? Motion.reduced : Motion.glowBloom, value: toolCallActive)
        .allowsHitTesting(false)
    }
}
