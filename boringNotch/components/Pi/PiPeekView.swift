//
//  PiPeekView.swift
//  boringNotch
//
//  The collapsed live-activity for a running Pi turn. Deliberately quiet — it mirrors
//  MusicLiveActivity's three-slot layout exactly: toolkit logo on the outer left, the
//  black notch spacer in the middle, a tinted equalizer on the outer right. No colored
//  aurora and no phase text, so it reads as a small ambient indicator rather than a
//  distracting lit panel. The richer toolkit gradient/accent lives in the *expanded*
//  Pi tab (PiAgentView), not here.
//
//  Right slot: the equalizer animates while a turn runs, and shows a brief green ✓ on
//  completion (the peek auto-hides shortly after via schedulePiPeekHide).
//

import SwiftUI

struct PiPeekView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var pi = PiAgentManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var logoNamespace: Namespace.ID

    private var slot: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    /// One wing's width — shared by the left (logo) and right (equalizer) slots.
    ///
    /// The peek is screen-centered and the physical notch is screen-centered, so the
    /// black spacer only lines up with the camera housing when both wings are equal.
    /// With no phase text the wings are compact and symmetric: each just holds a
    /// slot-sized icon (logo / equalizer) plus its outer padding — far narrower (and
    /// quieter) than the old text-sized wing.
    private var wingWidth: CGFloat {
        // 14pt outer padding + a slot-sized icon box on each side.
        let natural = slot + 14
        // Cap so two wings + the notch never outgrow the host window.
        let cap = (windowSize.width - vm.closedNotchSize.width) / 2 - 8
        return min(cap, natural)
    }

    private var waveTint: NSColor {
        pi.toolkitAccent ?? NSColor.effectiveAccent
    }

    /// True briefly after a turn finishes — the right slot shows a green ✓ instead of
    /// the equalizer until the peek auto-hides.
    private var showDoneCheck: Bool {
        !pi.isRunning && pi.statusWord == "done"
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

            // RIGHT — equalizer (or a brief ✓ on completion), pinned to the outer edge to
            // mirror the left logo. No phase text: the peek stays quiet.
            rightContent
                .frame(width: slot, height: slot, alignment: .center)
                .padding(.trailing, 14)
                .frame(width: wingWidth, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .animation(Motion.resolved(Motion.textSwapIn, reduceMotion: reduceMotion), value: showDoneCheck)
    }

    /// Right slot: the tinted equalizer while a turn runs, swapped for a brief green ✓
    /// on completion. Mirrors MusicLiveActivity's spectrum slot — no text.
    @ViewBuilder
    private var rightContent: some View {
        if showDoneCheck {
            Image(systemName: "checkmark")
                .font(.system(size: max(9, slot * 0.42), weight: .bold))
                .foregroundStyle(.green)
        } else {
            PiThinkingBarsView(isActive: pi.isRunning, tint: waveTint)
        }
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

}
