//
//  PiPeekView.swift
//  boringNotch
//
//  The collapsed live-activity for a running Pi turn. Mirrors MusicLiveActivity's
//  three-slot layout: toolkit logo (with a colored glow) on the left, the black
//  notch spacer in the middle, the current phase text + a tinted wave on the right.
//
//  Phase text precedence: forming tool (shimmer) → executing tool (solid, accent)
//  → "✓ Done" → status word.
//

import SwiftUI

struct PiPeekView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var pi = PiAgentManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var logoNamespace: Namespace.ID

    private var slot: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    /// Flair color sampled from the active toolkit logo, or the app accent as a
    /// fallback (idle / before a logo loads).
    private var accentColor: Color {
        if let c = pi.toolkitAccent { return Color(nsColor: c) }
        return Color.effectiveAccent
    }

    private var waveTint: NSColor {
        pi.toolkitAccent ?? NSColor.effectiveAccent
    }

    var body: some View {
        HStack(spacing: 0) {
            // LEFT — toolkit logo with a colored glow (morphs to/from the tab).
            // Breathing room on both sides: 14pt outer edge, 14pt before the cutout.
            logo
                .frame(width: slot, height: slot)
                .background(glow)
                .matchedGeometryEffect(id: "piLogo", in: logoNamespace)
                .padding(.leading, 14)
                .padding(.trailing, 14)

            // CENTER — the physical notch gap.
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width)

            // RIGHT — phase text (shimmer while forming, tinted while executing) + the wave.
            HStack(spacing: 8) {
                peekLabel
                    .id(peekText)
                    .transition(Motion.transition(Motion.textSwap, reduceMotion: reduceMotion))
                PiThinkingBarsView(isActive: pi.isRunning, tint: waveTint)
            }
            .frame(width: max(slot, 96), alignment: .leading)
            .padding(.leading, 16)
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

    /// Soft colored glow behind the logo — blooms in while a run is active. The
    /// toolkit color arrives as early as `tool_forming` (logo loads then), so the
    /// bloom takes on the real app's flair before the tool even executes.
    private var glow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [accentColor.opacity(0.75), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: slot * 0.9
                )
            )
            .frame(width: slot * 1.7, height: slot * 1.7)
            .blur(radius: slot * 0.18)
            .opacity(pi.isRunning ? 0.85 : 0)
            .scaleEffect(pi.isRunning ? 1 : 0.6)
            .animation(
                reduceMotion ? Motion.reduced : Motion.glowBloom,
                value: pi.isRunning
            )
            .allowsHitTesting(false)
    }

    /// The right-slot label for the current phase. Forming tools shimmer; executing
    /// tools sit solid in the toolkit accent; everything else is resting gray.
    @ViewBuilder
    private var peekLabel: some View {
        if pi.isForming {
            PiShimmerText(text: peekText, baseColor: .gray, active: true)
        } else {
            Text(peekText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(pi.isRunning ? accentColor : .gray)
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
