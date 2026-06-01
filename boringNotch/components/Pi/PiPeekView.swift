//
//  PiPeekView.swift
//  boringNotch
//
//  The collapsed live-activity for a running Pi turn. Mirrors MusicLiveActivity's
//  three-slot layout: toolkit logo on the left, the black notch spacer in the
//  middle, a one-word status + thinking bars on the right.
//

import SwiftUI

struct PiPeekView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var pi = PiAgentManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var logoNamespace: Namespace.ID

    private var slot: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    var body: some View {
        HStack(spacing: 0) {
            // LEFT — toolkit logo (morphs to/from the expanded tab).
            logo
                .frame(width: slot, height: slot)
                .matchedGeometryEffect(id: "piLogo", in: logoNamespace)

            // CENTER — the physical notch gap.
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width)

            // RIGHT — one-word status + thinking bars.
            HStack(spacing: 4) {
                Text(pi.statusWord)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.opacity)
                PiThinkingBarsView(isActive: pi.isRunning)
            }
            .frame(width: max(slot, 56), alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    private var logo: some View {
        if let image = pi.toolkitLogo {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: max(10, slot * 0.5)))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: slot, height: slot)
        }
    }
}
