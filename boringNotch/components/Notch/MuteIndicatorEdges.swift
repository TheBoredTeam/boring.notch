//
//  MuteIndicatorEdges.swift
//  boringNotch
//

import SwiftUI

/// Red glow on the closed notch's side edges while the microphone is muted,
/// clipped to the notch outline so it follows the corners.
struct MuteIndicatorEdges: View {
    let isNotchClosed: Bool
    let shape: NotchShape

    @ObservedObject private var microphone = MicrophoneManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flareCount = 0

    var body: some View {
        let isMuted = microphone.isMuted
        // Muting sweeps the glow in from the outer edges, overshooting a
        // little, while it flares up and settles back to its resting red.
        let extent: CGFloat = isMuted || reduceMotion ? 1 : 0.001
        let sweep: Animation = isMuted ? .spring(response: 0.35, dampingFraction: 0.55) : .easeIn(duration: 0.15)

        KeyframeAnimator(initialValue: 1.0, trigger: flareCount) { intensity in
            HStack(spacing: 0) {
                MuteGlow(edge: .leading, intensity: intensity)
                    .animation(sweep) { $0.scaleEffect(x: extent, anchor: .leading) }
                Spacer(minLength: 0)
                MuteGlow(edge: .trailing, intensity: intensity)
                    .animation(sweep) { $0.scaleEffect(x: extent, anchor: .trailing) }
            }
        } keyframes: { _ in
            CubicKeyframe(1.5, duration: 0.12)
            CubicKeyframe(1, duration: 0.5)
        }
        // With Reduce Motion the glow fades instead.
        .animation(.easeInOut(duration: 0.2)) {
            $0.opacity(isMuted || !reduceMotion ? 1 : 0)
        }
        // Gone as soon as the notch starts opening, and back once it has
        // mostly closed so it doesn't ride the shrinking panel.
        .animation(isNotchClosed ? .easeOut(duration: 0.25).delay(0.2) : .easeOut(duration: 0.1)) {
            $0.opacity(isNotchClosed ? 1 : 0)
        }
        .mask(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isMuted) { _, muted in
            if muted && !reduceMotion { flareCount += 1 }
        }
    }
}

/// Deep red at the outer edge, fading out towards the middle of the notch.
private struct MuteGlow: View {
    let edge: HorizontalEdge
    /// 1 at rest; the flare pushes it up to full red for a moment.
    var intensity: Double = 1

    private let red = Color(red: 0.95, green: 0.2, blue: 0.24)

    var body: some View {
        // The notch's straight sides start about 6pt in (its top corner
        // radius), so the stops are placed around that point.
        LinearGradient(
            stops: [
                .init(color: red.opacity(min(1, 0.9 * intensity)), location: 0),
                .init(color: red.opacity(min(1, 0.68 * intensity)), location: 0.375),
                .init(color: red.opacity(min(1, 0.18 * intensity)), location: 0.625),
                .init(color: red.opacity(0), location: 1)
            ],
            startPoint: edge == .leading ? .leading : .trailing,
            endPoint: edge == .leading ? .trailing : .leading
        )
        .frame(width: 16)
    }
}
