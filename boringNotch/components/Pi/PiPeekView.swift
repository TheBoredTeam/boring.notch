//
//  PiPeekView.swift
//  boringNotch
//
//  The collapsed live-activity for a running Pi turn. Mirrors MusicLiveActivity's
//  three-slot layout: toolkit logo (with a colored glow) on the left, the black
//  notch spacer in the middle, the current phase text + a tinted wave on the right —
//  the right slot rides on a two-hue "edge bloom" gradient that expands while a tool
//  call is in flight and shrinks back while the model is just thinking.
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

    /// Flair color sampled from the active toolkit logo, or the app accent as a
    /// fallback (idle / before a logo loads).
    private var accentColor: Color {
        if let c = pi.toolkitAccent { return Color(nsColor: c) }
        return Color.effectiveAccent
    }

    private var waveTint: NSColor {
        pi.toolkitAccent ?? NSColor.effectiveAccent
    }

    /// The accent hue-shifted toward indigo — the second stop of the edge bloom, so
    /// the gradient reads as a two-hue aurora (gmail red→violet, calendar blue→indigo)
    /// instead of a flat single-color glow.
    private var companionColor: Color {
        let base = pi.toolkitAccent ?? NSColor.effectiveAccent
        let shifted = base.blended(withFraction: 0.6, of: .systemIndigo) ?? base
        return Color(nsColor: shifted)
    }

    /// True while the model is forming or executing a tool call — drives the bloom's
    /// expansion. Plain thinking keeps it small; tool work makes it swell.
    private var toolCallActive: Bool {
        pi.isForming || pi.currentTool != nil
    }

    var body: some View {
        HStack(spacing: 0) {
            // LEFT — toolkit logo with a colored glow (morphs to/from the tab).
            // Pinned to the outer edge of a full wing so the center spacer stays
            // glued to the physical notch.
            logo
                .frame(width: slot, height: slot)
                .background(glow)
                .matchedGeometryEffect(id: "piLogo", in: logoNamespace)
                .padding(.leading, 14)
                .frame(width: wingWidth, alignment: .leading)

            // CENTER — the physical notch gap.
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width)

            // RIGHT — phase text (shimmer while forming, tinted while executing) pushed
            // apart from the wave, both riding on the edge bloom.
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
            .background(edgeBloom)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
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

    /// Soft colored glow behind the logo — blooms in while a run is active and swells
    /// further while a tool call is in flight. The toolkit color arrives as early as
    /// `tool_forming` (logo loads then), so the bloom takes on the real app's flair
    /// before the tool even executes.
    private var glow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [accentColor.opacity(0.8), companionColor.opacity(0.4), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: slot * 0.9
                )
            )
            .frame(width: slot * 1.7, height: slot * 1.7)
            .blur(radius: slot * 0.18)
            .opacity(pi.isRunning ? (toolCallActive ? 1 : 0.7) : 0)
            .scaleEffect(pi.isRunning ? (toolCallActive ? 1.15 : 0.85) : 0.6)
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

    /// The screenshot-style aurora bleeding in from the peek's outer edge: a two-hue
    /// elliptical gradient (toolkit accent → indigo companion → clear) anchored at the
    /// trailing edge behind the wave. It expands while a tool call is in flight,
    /// settles back while the model is just thinking, and collapses when the run ends.
    private var edgeBloom: some View {
        EllipticalGradient(
            colors: [
                accentColor.opacity(0.65),
                companionColor.opacity(0.35),
                .clear,
            ],
            center: .trailing,
            startRadiusFraction: 0,
            endRadiusFraction: 0.95
        )
        .scaleEffect(
            x: toolCallActive ? 1.0 : 0.55,
            y: toolCallActive ? 1.0 : 0.75,
            anchor: .trailing
        )
        .blur(radius: 7)
        .opacity(pi.isRunning ? (toolCallActive ? 1 : 0.5) : 0)
        .animation(
            reduceMotion ? Motion.reduced : Motion.glowBloom,
            value: toolCallActive
        )
        .animation(
            reduceMotion ? Motion.reduced : Motion.glowBloom,
            value: pi.isRunning
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
