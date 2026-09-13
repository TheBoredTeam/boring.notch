//
//  NotchVisualizerBackground.swift
//  boringNotch
//
//  Created by Claude on 2026-07-05.
//

import Defaults
import SwiftUI

/// Ambient, beat-like animated background rendered behind the open notch content
/// while music is playing. Uses smooth pseudo-random waves (like the existing
/// AudioSpectrum, no real audio data) tinted with the album art color.
struct NotchVisualizerBackground: View {
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.visualizerBackgroundStyle) var style
    @Default(.visualizerBackgroundIntensity) var intensity
    @Default(.playerColorTinting) var playerColorTinting

    private let barCount = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !musicManager.isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            switch style {
            case .bars:
                barsCanvas(time: time)
            case .pulse:
                pulseGradient(time: time)
            }
        }
        .opacity(Double(max(0.1, min(1, intensity * 2))))
        .allowsHitTesting(false)
    }

    private var tintColor: Color {
        playerColorTinting
            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.8)
            : Color(white: 0.75)
    }

    private func barsCanvas(time: TimeInterval) -> some View {
        let barColor = tintColor
        return Canvas { context, size in
            let barWidth = size.width / CGFloat(barCount * 2 - 1)
            for index in 0..<barCount {
                let level = barLevel(index: index, time: time)
                let barHeight = size.height * (0.2 + 0.75 * level)
                let x = CGFloat(index * 2) * barWidth
                let rect = CGRect(
                    x: x,
                    y: size.height - barHeight,
                    width: barWidth,
                    height: barHeight
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .linearGradient(
                        Gradient(colors: [barColor.opacity(0.15), barColor]),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                    )
                )
            }
        }
        .blur(radius: 8)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.45),
                    .init(color: .white, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func pulseGradient(time: TimeInterval) -> some View {
        let pulse = 0.5 + 0.5 * sin(time * 2.1)
        return RadialGradient(
            colors: [tintColor, .clear],
            center: .bottom,
            startRadius: 0,
            endRadius: 300 + 120 * pulse
        )
        .opacity(0.6 + 0.4 * pulse)
    }

    /// Smooth wave-based pseudo level per bar; layered sines look organic
    /// without needing mutable random-walk state.
    private func barLevel(index: Int, time: TimeInterval) -> CGFloat {
        let phase = Double(index) * 0.9
        let primary = sin(time * (1.6 + Double(index % 5) * 0.35) + phase)
        let secondary = sin(time * 3.1 + phase * 1.7)
        let combined = 0.5 + 0.35 * primary + 0.15 * secondary
        return CGFloat(min(1, max(0, combined)))
    }
}

#Preview {
    NotchVisualizerBackground()
        .frame(width: 600, height: 180)
        .background(.black)
}
