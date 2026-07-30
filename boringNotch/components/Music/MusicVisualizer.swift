//
//  MusicVisualizer.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//
import Defaults
import SwiftUI

/// The four bars shown next to the album art while music plays.
///
/// The bars follow the real output spectrum whenever the system audio tap is
/// running (see `AudioSpectrumManager`); otherwise they fall back to the
/// original random dance, so the notch never looks dead.
///
/// Each bar is a `Capsule`, which keeps the rounded caps at every height. The
/// previous implementation drew a rounded `CAShapeLayer` path but also set an
/// opaque `backgroundColor` on the same layer, so the square layer rect was
/// what actually showed up — and animating `transform.scale.y` flattened any
/// corner radius along with the bar.
struct AudioSpectrumView: View {
    @Binding var isPlaying: Bool

    @ObservedObject private var spectrum = AudioSpectrumManager.shared
    @Default(.realtimeAudioSpectrum) private var realtimeSpectrumEnabled
    @Environment(\.displayScale) private var displayScale

    /// Identifies this visualiser to the shared tap; stable for the view's life.
    @State private var token = UUID()
    @State private var fallbackLevels: [CGFloat] = .init(
        repeating: 0, count: audioSpectrumBandCount
    )
    @State private var fallbackTask: Task<Void, Never>?

    private static let fallbackInterval: Duration = .milliseconds(300)

    private var usesRealAudio: Bool { realtimeSpectrumEnabled && spectrum.isLive }

    private var levels: [CGFloat] { usesRealAudio ? spectrum.levels : fallbackLevels }

    private var animation: Animation {
        usesRealAudio ? .linear(duration: 1.0 / 30.0) : .easeInOut(duration: 0.3)
    }

    var body: some View {
        GeometryReader { proxy in
            // Bar widths are snapped to whole device pixels. At these sizes a
            // fractional width lands each capsule on a different subpixel
            // offset, and the anti-aliasing makes the bars look like they have
            // different thicknesses.
            let bars = CGFloat(audioSpectrumBandCount)
            let raw = proxy.size.width / (bars * 2 - 1)
            let barWidth = snapped(raw, minimum: 1)
            let gap = snapped(
                (proxy.size.width - barWidth * bars) / max(1, bars - 1), minimum: 1
            )

            HStack(alignment: .center, spacing: gap) {
                ForEach(0 ..< audioSpectrumBandCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(Color.white)
                        .frame(
                            width: barWidth,
                            height: barHeight(
                                for: index,
                                barWidth: barWidth,
                                maxHeight: proxy.size.height
                            )
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            .animation(animation, value: levels)
        }
        .onAppear { synchronize() }
        .onDisappear {
            stopFallback()
            spectrum.deactivate(token)
        }
        .onChange(of: isPlaying) { _, _ in synchronize() }
        .onChange(of: realtimeSpectrumEnabled) { _, _ in synchronize() }
        .onChange(of: spectrum.isLive) { _, _ in synchronize() }
    }

    /// Rounds a length to a whole device pixel.
    private func snapped(_ value: CGFloat, minimum: CGFloat) -> CGFloat {
        let scale = max(1, displayScale)
        return max(minimum / scale, (value * scale).rounded() / scale)
    }

    /// At rest a bar is a dot; at full level it fills the frame.
    private func barHeight(for index: Int, barWidth: CGFloat, maxHeight: CGFloat) -> CGFloat {
        guard maxHeight > barWidth else { return max(0, maxHeight) }
        let level = index < levels.count ? min(max(levels[index], 0), 1) : 0
        return snapped(barWidth + (maxHeight - barWidth) * level, minimum: 1)
    }

    // MARK: - Sources

    private func synchronize() {
        if isPlaying && realtimeSpectrumEnabled {
            spectrum.activate(token)
        } else {
            spectrum.deactivate(token)
        }

        if isPlaying && !usesRealAudio {
            startFallback()
        } else {
            stopFallback()
        }
    }

    private func startFallback() {
        guard fallbackTask == nil else { return }
        fallbackTask = Task { @MainActor in
            while !Task.isCancelled {
                fallbackLevels = (0 ..< audioSpectrumBandCount).map { _ in
                    CGFloat.random(in: 0.2 ... 1.0)
                }
                try? await Task.sleep(for: Self.fallbackInterval)
            }
        }
    }

    private func stopFallback() {
        fallbackTask?.cancel()
        fallbackTask = nil
        if fallbackLevels.contains(where: { $0 != 0 }) {
            fallbackLevels = .init(repeating: 0, count: audioSpectrumBandCount)
        }
    }
}

#Preview {
    AudioSpectrumView(isPlaying: .constant(true))
        .frame(width: 16, height: 12)
        .padding()
        .background(.black)
}
