//  DropZoneView.swift
//  IslandNotch
//
//  Purpose: Visual highlight shown while the user is dragging an image over the
//           notch shelf, signalling that a drop will be accepted.
//  Layer: View

import SwiftUI

struct DropZoneView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var breathing = false
    @State private var dashPhase: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                Color.accentColor,
                style: StrokeStyle(lineWidth: 2, dash: [6, 4], dashPhase: dashPhase)
            )
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(breathing ? 0.20 : 0.12))
            )
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .offset(y: breathing ? 2 : -2)
                    Text("Drop your image here")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(Color.accentColor)
                .padding(8)
            }
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                // The breathing pulse is continuous on-screen movement, so it uses
                // ease-in-out (natural acceleration/deceleration) rather than the old
                // ease-out, which only suits one-shot entrances.
                withAnimation(Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    breathing = true
                }
                // Constant-speed dash march reads as "active / ready" — constant motion
                // wants linear timing. One dash period is 6 + 4 = 10pt.
                withAnimation(Animation.linear(duration: 0.6).repeatForever(autoreverses: false)) {
                    dashPhase = -10
                }
            }
    }
}
