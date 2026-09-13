//
//  CustomMusicVisualizer.swift
//  boringNotch
//
//  A smooth, time-driven equalizer for the music live activity. Each bar is
//  driven by a blend of two sine waves at staggered (deterministic) phases and
//  speeds, so the motion looks organic rather than the old random per-tick
//  jumps. Animation is paused — and bars settle to a low resting height — when
//  playback is paused.
//

import SwiftUI

struct CustomMusicVisualizer: View {
    var isPlaying: Bool
    var color: Color
    var barCount: Int = 4

    // Resting height as a fraction of the full bar height when paused / at troughs.
    private let minRatio: CGFloat = 0.22

    // Deterministic per-bar phase/speed so re-inits don't cause visual jumps.
    private func phase(_ i: Int) -> Double { Double(i) * 0.9 }
    private func speed(_ i: Int) -> Double { 3.4 + Double(i) * 0.45 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let spacing = geo.size.width * 0.22 / CGFloat(max(1, barCount))
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0 ..< barCount, id: \.self) { i in
                        Capsule()
                            .fill(color)
                            .frame(height: barHeight(i, t: t, maxHeight: geo.size.height))
                            .animation(.easeInOut(duration: 0.12), value: isPlaying)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func barHeight(_ i: Int, t: Double, maxHeight: CGFloat) -> CGFloat {
        guard isPlaying else { return maxHeight * minRatio }
        let primary = (sin(t * speed(i) + phase(i)) + 1) / 2          // 0...1
        let detail = (sin(t * speed(i) * 0.5 + phase(i) * 1.7) + 1) / 2 // 0...1
        let mixed = CGFloat(0.65 * primary + 0.35 * detail)
        return maxHeight * (minRatio + (1 - minRatio) * mixed)
    }
}

#Preview {
    CustomMusicVisualizer(isPlaying: true, color: .green)
        .frame(width: 24, height: 14)
        .padding()
        .background(.black)
}
