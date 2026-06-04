//
//  PiPeekView.swift
//  boringNotch
//
//  The collapsed live-activity for a running Pi turn. Mirrors MusicLiveActivity's
//  three-slot layout: toolkit logo on the left, the black notch spacer in the middle,
//  the current phase text + a tinted wave on the right.
//
//  Behind all three slots sits ONE continuous brand-colored aurora (`aurora`). The
//  opaque black center spacer masks it where the physical notch is, so the color reads
//  as the notch itself glowing at both wings and spilling into its rounded bottom
//  corners — not two separate blobs floating on black. The parent NotchShape clip
//  (ContentView) trims the bleed to the notch silhouette. It swells while a tool call
//  is in flight and collapses to nothing at rest.
//
//  Phase text precedence: forming tool (shimmer) → executing tool (solid, white)
//  → "✓ Done" → status word.
//

import SwiftUI

struct PiPeekView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var pi = PiAgentManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var logoNamespace: Namespace.ID

    private var slot: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    /// One wing's width — shared by the left (logo) and right (text + wave) slots.
    ///
    /// The peek is screen-centered and the physical notch is screen-centered, so the
    /// black spacer only lines up with the camera housing when both wings are equal.
    /// Unequal wings shift the spacer off-center and the phase text slides under the
    /// real notch. The wing is sized to the live phase text so longer labels widen
    /// the notch instead of hiding or truncating.
    private var wingWidth: CGFloat {
        // Measure peekText at the label font (11pt semibold rounded, 0.2 kerning).
        let base = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let font = NSFont(descriptor: descriptor, size: 11) ?? base
        let textWidth = ceil(
            (peekText as NSString).size(withAttributes: [.font: font, .kern: 0.2]).width
        )
        // Right slot naturals: 18 leading + text + 10 gap + 16 wave + 16 trailing.
        let rightNatural = 18 + textWidth + 10 + 16 + 16
        // Left slot naturals: 14 leading + logo + 14 trailing.
        let leftNatural = slot + 28
        // Cap so two wings + the notch never outgrow the host window.
        let cap = (windowSize.width - vm.closedNotchSize.width) / 2 - 8
        return min(cap, max(148, rightNatural, leftNatural))
    }

    private var waveTint: NSColor {
        pi.toolkitAccent ?? NSColor.effectiveAccent
    }

    /// The companion hue used to give a *single-color* (or empty) toolkit mark a second
    /// stop, so a mono logo's aurora still has internal depth instead of one flat pool.
    /// A clamped ≤40° analogous shift of the dominant color toward the palette's second
    /// hue — or a synthetic +30° when there's only one hue. The cap keeps the two hues
    /// analogous so they read as one aurora, not a rainbow. Multi-color logos don't use
    /// this — they paint their real palette directly (see `auroraPalette`). Near-gray /
    /// empty palette → indigo. HSB-based, hue-wrap-safe.
    private var companionColor: Color {
        let palette = pi.toolkitPalette
        guard let first = palette.first?.usingColorSpace(.sRGB) else {
            return Color(nsColor: .systemIndigo)
        }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        first.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Near-gray mono mark: no meaningful hue to shift → indigo companion.
        if s < 0.15 { return Color(nsColor: .systemIndigo) }

        let targetHue: CGFloat
        if palette.count > 1, let second = palette[1].usingColorSpace(.sRGB) {
            var h2: CGFloat = 0, s2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            second.getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2)
            targetHue = h2
        } else {
            // Single hue → synthetic +30° analogous companion.
            targetHue = (h + 30.0 / 360.0).truncatingRemainder(dividingBy: 1.0)
        }

        // Signed wrap-aware delta on the 0...1 wheel, clamped to ≤40°.
        var delta = targetHue - h
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        let maxShift: CGFloat = 40.0 / 360.0
        let clamped = max(-maxShift, min(maxShift, delta))
        var companionHue = (h + clamped).truncatingRemainder(dividingBy: 1.0)
        if companionHue < 0 { companionHue += 1 }

        return Color(nsColor: NSColor(hue: companionHue, saturation: s, brightness: b, alpha: 1))
    }

    /// Anchor points for the palette blooms, spread across the peek so each toolkit
    /// color lands in its own region (mirrors `ANCH` in docs/pi-peek-toolkit-palette.html).
    /// The center-ish anchors fall under the opaque black spacer and are simply hidden —
    /// the wings get the dominant + outer colors.
    private static let auroraAnchors: [UnitPoint] = [
        .init(x: 0.08, y: 0.30),
        .init(x: 0.42, y: 0.82),
        .init(x: 0.78, y: 0.20),
        .init(x: 1.00, y: 0.70),
        .init(x: 0.55, y: 0.48),
    ]

    /// Anchors for RAW curated overrides — mirrors the mockup's `meshCss` layout
    /// (`docs/pi-brand-palette-manifest.html` `ANCH`), but the mockup paints across a
    /// continuous bar including dead-center, whereas the real notch masks its center with
    /// the camera housing. So the mockup's center stop is remapped onto a visible wing —
    /// no stop is lost behind the notch. Order follows the manifest stops: stop0 dominant
    /// (left), stop1 (right), stop2 grounding note (lower-right, off the masked center).
    private static let overrideAnchors: [UnitPoint] = [
        .init(x: 0.10, y: 0.28),   // stop0 — dominant hue, left wing      (mockup 18%,28%)
        .init(x: 0.88, y: 0.34),   // stop1 — right wing                   (mockup 78%,34%)
        .init(x: 0.80, y: 0.80),   // stop2 — grounding note, lower-right  (mockup 50%,70% → off-center)
        .init(x: 0.16, y: 0.78),   // spare — lower-left wing
        .init(x: 0.50, y: 0.48),   // spare — masked center (unused by 2–3 stop overrides)
    ]

    /// The toolkit's brand palette as `(color, weight)` pairs the aurora paints directly,
    /// rather than averaging them into one muddy blob (see the toolkit-palette spec). A
    /// single-hue mark is paired with its `companionColor` for two-hue depth; an empty
    /// palette falls back to indigo + companion. Capped at five (the anchor count).
    ///
    /// Two render modes, keyed by `pi.toolkitPaletteIsRaw`:
    /// - **Raw curated override** — the manifest stops, verbatim (`rawColor`, no `deepen`
    ///   distortion). Each stop's per-stop `weight` (the mockup's `*0.55` highlight)
    ///   travels in the source color's alpha; we lift it out here so the bloom can shrink
    ///   + dim it exactly like the mockup. White stays white, black stays black.
    /// - **Derived palette** — re-saturated via `deepen` (undoing `legibleTint`'s wash for
    ///   text); weight is always 1, so these render identically to before.
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
        return Array(base.prefix(Self.auroraAnchors.count))
    }

    /// A curated stop → SwiftUI `Color`, verbatim — no `deepen` re-saturation, so the
    /// hand-picked mockup hues (white highlight, black grounding, brand colors) land
    /// exactly as authored. The weight rides in `ns`'s alpha; we force opacity 1 here and
    /// apply the weight as a bloom multiplier in `aurora` instead.
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
        // Near-gray stays near-gray (mono marks) — only deepen real hues.
        let ds = s < 0.12 ? s : max(s, 0.85)
        let db = min(b, 0.80)
        return Color(nsColor: NSColor(hue: h, saturation: ds, brightness: db, alpha: 1))
    }

    /// True while the model is forming or executing a tool call — drives the bloom's
    /// expansion. Plain thinking keeps it small; tool work makes it swell.
    private var toolCallActive: Bool {
        pi.isForming || pi.currentTool != nil
    }

    var body: some View {
        HStack(spacing: 0) {
            // LEFT — toolkit logo (morphs to/from the tab). Pinned to the outer edge of
            // a full wing so the center spacer stays glued to the physical notch.
            logo
                .frame(width: slot, height: slot)
                .matchedGeometryEffect(id: "piLogo", in: logoNamespace)
                .padding(.leading, 14)
                .frame(width: wingWidth, alignment: .leading)

            // CENTER — the physical notch gap. Opaque black: it doubles as the mask that
            // hides the aurora behind the camera housing so the wings glow, not the gap.
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width)

            // RIGHT — phase text (shimmer while forming, tinted while executing) pushed
            // apart from the wave.
            HStack(spacing: 10) {
                peekLabel
                    .id(peekText)
                    .transition(Motion.transition(Motion.textSwap, reduceMotion: reduceMotion))
                Spacer(minLength: 10)
                PiThinkingBarsView(isActive: pi.isRunning, tint: waveTint)
            }
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .frame(width: wingWidth, alignment: .leading)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        // One continuous aurora behind the whole peek; the black center spacer above
        // masks its middle so only the wings glow. Sits under the content.
        //
        // It bleeds out past ContentView's closed-state horizontal inset
        // (`cornerRadiusInsets.closed.bottom`) so the glow reaches the *real* notch
        // silhouette edges instead of floating inset — the parent NotchShape clip then
        // trims the bleed to the rounded chin, so the color reads as the notch itself
        // glowing. Without the bleed the aurora showed as a boxy rounded rect tucked
        // inside the notch, its near-square top corners reading as "squared up".
        .background(aurora.padding(.horizontal, -cornerRadiusInsets.closed.bottom))
        .animation(Motion.resolved(Motion.textSwapIn, reduceMotion: reduceMotion), value: peekText)
    }

    /// Logo precedence: live per-toolkit metadata logo → bundled Composio mark →
    /// `sparkles`. Never blank.
    @ViewBuilder
    private var logo: some View {
        if let image = pi.toolkitLogo {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if let composio = NSImage(named: "composio-mark") {
            let _ = (composio.isTemplate = true)   // force AppKit template mask → tints to foregroundStyle
            Image(nsImage: composio)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white.opacity(0.92))
                .padding(slot * 0.12)
                .frame(width: slot, height: slot)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: max(10, slot * 0.5)))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: slot, height: slot)
        }
    }

    /// The aurora behind the whole peek: one additive radial bloom per brand color,
    /// anchored across the peek (the recipe from docs/pi-peek-toolkit-palette.html).
    ///
    /// The pools are drawn over an explicit black base with `.plusLighter` so they add
    /// like light — deep, saturated color where each anchor sits, true black between —
    /// which is the mockup's "dark, strong color" look, not a flat pastel wash. Drawing
    /// over our own black base (inside a `compositingGroup`) makes the additive blend
    /// deterministic instead of depending on whatever sits behind the background. The
    /// opaque center spacer in `body` hides the middle, so only the wings light up.
    ///
    /// The rounded clip (bottom corners matching the notch's 20pt chin) keeps it from
    /// reading as a boxy rectangle; `blur` melts the pool seams. Fades up while running,
    /// swells while a tool call is in flight, collapses at rest.
    private var aurora: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Underglow only. The big wing-spanning blooms read as a distracting colored
            // field washing onto the screen, so collapse them to two soft pools of the
            // brand color tucked *under* the chin — the dominant stop on the left wing, its
            // companion on the right. The pool centers sit just below the bottom edge
            // (y > 1) so only the gentle upper falloff is visible; clipped to the chin it
            // reads as light spilling from the notch's rounded bottom, not a lit panel.
            // The center spacer in `body` still masks the camera housing between them.
            let left = auroraStops.first?.color ?? Color(nsColor: .systemIndigo)
            let right = auroraStops.count > 1 ? auroraStops[1].color : companionColor
            ZStack {
                Color.black
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: left.opacity(0.72), location: 0),
                        .init(color: left.opacity(0), location: 0.62),
                    ]),
                    center: UnitPoint(x: 0.14, y: 1.08),
                    startRadius: 0,
                    endRadius: w * 0.55
                )
                .blendMode(.screen)
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: right.opacity(0.72), location: 0),
                        .init(color: right.opacity(0), location: 0.62),
                    ]),
                    center: UnitPoint(x: 0.86, y: 1.08),
                    startRadius: 0,
                    endRadius: w * 0.55
                )
                .blendMode(.screen)
            }
            .frame(width: w, height: h)
        }
        .compositingGroup()
        .blur(radius: 5)
        // Vertical fade, bottom-biased to match the underglow: the color is fully present
        // along the chin and dissolves to clear toward the top, so any stray glow can't
        // reach the top corners and the notch reads as lit only at its rounded bottom.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .white.opacity(0.55), location: 0.5),
                    .init(color: .white, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // Clip to the actual notch silhouette (not a plain rounded rect) so the bled
        // glow hugs the rounded 20pt chin exactly the way the parent NotchShape does —
        // rounded corners, no boxy lit panel floating inside. With the fade above, the
        // chin it rounds is already black, so no hard color edge remains.
        .clipShape(
            NotchShape(
                topCornerRadius: cornerRadiusInsets.closed.top,
                bottomCornerRadius: 20
            )
        )
        .scaleEffect(y: toolCallActive ? 1.0 : 0.96, anchor: .bottom)
        .opacity(pi.isRunning ? (toolCallActive ? 1.0 : 0.78) : 0)
        .animation(
            reduceMotion ? Motion.reduced : Motion.glowBloom,
            value: pi.isRunning
        )
        .animation(
            reduceMotion ? Motion.reduced : Motion.glowBloom,
            value: toolCallActive
        )
        .allowsHitTesting(false)
    }

    /// The right-slot label for the current phase. Forming tools shimmer; executing
    /// tools sit solid in white (they ride on the colored bloom, so white reads
    /// cleaner than accent-on-accent); everything else is resting gray.
    @ViewBuilder
    private var peekLabel: some View {
        if pi.isForming {
            PiShimmerText(
                text: peekText,
                baseColor: .gray,
                active: true,
                font: .system(size: 11, weight: .semibold, design: .rounded)
            )
        } else {
            Text(peekText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .kerning(0.2)
                .foregroundStyle(pi.isRunning ? .white : .gray)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Right-slot text: forming ("Calling a tool…" / shimmer name) → executing tool
    /// ("Send email") → "Thinking…" → "✓ Done" / "Stopped" / status word.
    private var peekText: String {
        if pi.isForming {
            return pi.formingToolPretty ?? "Calling a tool…"
        }
        if pi.isRunning {
            if let pretty = pi.currentToolPretty { return pretty }
            return "Thinking…"
        }
        switch pi.statusWord {
        case "done": return "✓ Done"
        case "aborted": return "Stopped"
        case "": return "Ready"
        default: return pi.statusWord.prefix(1).uppercased() + pi.statusWord.dropFirst()
        }
    }
}
