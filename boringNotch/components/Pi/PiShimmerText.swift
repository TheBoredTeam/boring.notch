//
//  PiShimmerText.swift
//  boringNotch
//
//  Shimmering text for a tool call that is still forming (the model is streaming
//  its arguments). A bright band sweeps across dimmed text via an animated gradient
//  mask — the mask offset is a transform, so the loop stays off the layout/paint
//  path. Under Reduce Motion the sweep is dropped and the text just sits dimmed.
//

import SwiftUI

struct PiShimmerText: View {
    let text: String
    /// Resting color of the text the shimmer sweeps across.
    var baseColor: Color = .gray
    /// Whether the shimmer loop runs. When false, renders as plain text.
    var active: Bool = true
    var font: Font = .system(size: 10, weight: .semibold, design: .rounded)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the gradient band across the text. -1 → off the left edge, 1 → off the right.
    @State private var phase: CGFloat = -1

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(baseColor.opacity(shimmering ? 0.6 : 1))
            .overlay {
                if shimmering {
                    sweep
                }
            }
            .onAppear { startIfNeeded() }
            .onChange(of: active) { _, _ in startIfNeeded() }
            .onChange(of: reduceMotion) { _, _ in startIfNeeded() }
    }

    /// The sweep runs only while active and motion is allowed; Reduce Motion gets
    /// static text at reduced opacity instead.
    private var shimmering: Bool { active && !reduceMotion }

    /// Bright copy of the text, masked to a moving band.
    private var sweep: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.white)
            .mask {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.8)
                    .offset(x: geo.size.width * phase)
                }
            }
            .allowsHitTesting(false)
    }

    private func startIfNeeded() {
        guard shimmering else {
            phase = -1
            return
        }
        phase = -1
        withAnimation(.linear(duration: Motion.shimmerPeriod).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}
