//
//  PiPeekView.swift
//  boringNotch
//
//  The collapsed live-activity for a running Pi turn. Mirrors MusicLiveActivity's
//  three-slot layout: toolkit logo (with a colored glow) on the left, the black
//  notch spacer in the middle, the sanitized current-tool text + a tinted wave on
//  the right.
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
            logo
                .frame(width: slot, height: slot)
                .background(glow)
                .matchedGeometryEffect(id: "piLogo", in: logoNamespace)

            // CENTER — the physical notch gap.
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width)

            // RIGHT — sanitized current-tool text (tinted when active) + the wave.
            HStack(spacing: 8) {
                Text(peekText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(pi.isRunning ? accentColor : .gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                PiThinkingBarsView(isActive: pi.isRunning, tint: waveTint)
            }
            .frame(width: max(slot, 96), alignment: .leading)
            .padding(.leading, 6)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .animation(Motion.resolved(Motion.flash, reduceMotion: reduceMotion), value: peekText)
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

    /// Soft colored glow behind the logo — blooms in while a run is active.
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
            .opacity(pi.isRunning ? 0.9 : 0)
            .scaleEffect(pi.isRunning ? 1 : 0.6)
            .animation(
                reduceMotion
                    ? Motion.reduced
                    : .spring(response: 0.42, dampingFraction: 0.72),
                value: pi.isRunning
            )
            .allowsHitTesting(false)
    }

    /// Right-slot label: "Thinking…" → sanitized tool ("Execute tool") → "Done".
    private var peekText: String {
        if pi.isRunning {
            if let pretty = pi.currentToolPretty { return pretty }
            return "Thinking…"
        }
        switch pi.statusWord {
        case "done": return "Done"
        case "aborted": return "Stopped"
        case "": return "Ready"
        default: return pi.statusWord.prefix(1).uppercased() + pi.statusWord.dropFirst()
        }
    }
}
