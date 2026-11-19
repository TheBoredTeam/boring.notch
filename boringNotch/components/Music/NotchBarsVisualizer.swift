//
//  NotchBarsVisualizer.swift
//  boringNotch
//
//  Thin spectrum bars that hang from the bottom edge of the closed notch while
//  real-time audio capture is running. Levels come from AudioCaptureManager.
//

import Defaults
import SwiftUI

struct NotchBarsVisualizer: View {
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.coloredSpectrogram) var coloredSpectrogram

    @State private var smoother = LevelSmoother()

    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 2
    private let minHeight: CGFloat = 2
    var maxHeight: CGFloat = 16

    private var barColor: Color {
        coloredSpectrogram ? Color(nsColor: musicManager.avgColor).opacity(0.95) : .white.opacity(0.9)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 40.0)) { timeline in
            Canvas { context, size in
                // Reading the date makes Canvas redraw on every tick instead of caching.
                _ = timeline.date
                // More notch width -> more bars; bar thickness stays constant.
                let count = max(1, Int((size.width + spacing) / (barWidth + spacing)))
                let used = CGFloat(count) * barWidth + CGFloat(count - 1) * spacing
                let originX = (size.width - used) / 2
                let bands = smoother.update(with: AudioCaptureManager.shared.latestLevelsSnapshot())
                for index in 0..<count {
                    let level = Self.sample(bands, at: index, of: count)
                    let height = minHeight + (maxHeight - minHeight) * CGFloat(level)
                    // Anchored to the notch's bottom edge, growing downward.
                    let rect = CGRect(x: originX + CGFloat(index) * (barWidth + spacing), y: 0, width: barWidth, height: height)
                    let bar = UnevenRoundedRectangle(bottomLeadingRadius: barWidth / 2, bottomTrailingRadius: barWidth / 2)
                        .path(in: rect)
                    context.fill(bar, with: .color(barColor))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: maxHeight)
    }

    /// Stretches the few analysis bands across `count` bars with smooth (cosine) interpolation.
    private static func sample(_ bands: [Float], at index: Int, of count: Int) -> Float {
        guard bands.count > 1, count > 1 else { return bands.first ?? 0 }
        let position = Float(index) / Float(count - 1) * Float(bands.count - 1)
        let lower = Int(position)
        let upper = min(lower + 1, bands.count - 1)
        let t = (1 - cos((position - Float(lower)) * .pi)) / 2
        return bands[lower] * (1 - t) + bands[upper] * t
    }
}

/// Eases band levels toward their targets: quick attack, slower release.
private final class LevelSmoother {
    private var current: [Float] = []

    func update(with target: [Float]?) -> [Float] {
        guard let target else { return current }
        if current.count != target.count {
            current = [Float](repeating: 0, count: target.count)
        }
        for i in target.indices {
            let coefficient: Float = target[i] > current[i] ? 0.5 : 0.15
            current[i] += (target[i] - current[i]) * coefficient
        }
        return current
    }
}
