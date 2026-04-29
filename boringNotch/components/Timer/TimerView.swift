//
//  TimerView.swift
//  boringNotch
//

import SwiftUI

private let presets: [(label: String, seconds: TimeInterval)] = [
    ("+1m",  60),
    ("+5m",  300),
    ("+10m", 600),
    ("+25m", 1500),
    ("+45m", 2700),
]

struct TimerView: View {
    @ObservedObject var timerManager = TimerManager.shared

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            Spacer(minLength: 16)
            ringPanel
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Left: presets + controls

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            presetGrid
            Spacer(minLength: 0)
            actionRow
        }
        .frame(maxHeight: .infinity)
    }

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(presets.prefix(3), id: \.label) { preset in
                    presetButton(preset)
                }
            }
            HStack(spacing: 6) {
                ForEach(presets.suffix(2), id: \.label) { preset in
                    presetButton(preset)
                }
            }
        }
    }

    private func presetButton(_ preset: (label: String, seconds: TimeInterval)) -> some View {
        Button {
            withAnimation(.smooth) {
                timerManager.addPreset(preset.seconds)
            }
        } label: {
            Text(preset.label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .fixedSize()
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(nsColor: .tertiarySystemFill)))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(timerManager.state == .running || timerManager.state == .finished)
        .opacity((timerManager.state == .running || timerManager.state == .finished) ? 0.35 : 1)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            switch timerManager.state {
            case .idle:
                startButton
            case .running:
                pauseButton
                resetButton
            case .paused:
                startButton
                resetButton
            case .finished:
                resetButton
            }
        }
    }

    private var startButton: some View {
        actionCapsule(icon: "play.fill", label: timerManager.state == .paused ? "Resume" : "Start") {
            timerManager.start()
        }
        .disabled(timerManager.remainingTime == 0)
        .opacity(timerManager.remainingTime == 0 ? 0.35 : 1)
    }

    private var pauseButton: some View {
        actionCapsule(icon: "pause.fill", label: "Pause") {
            timerManager.pause()
        }
    }

    private var resetButton: some View {
        HoverButton(icon: "arrow.counterclockwise", scale: .medium) {
            withAnimation(.smooth) { timerManager.reset() }
        }
    }

    private func actionCapsule(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.smooth) { action() }
        } label: {
            Capsule()
                .fill(Color(nsColor: .secondarySystemFill))
                .frame(height: 30)
                .overlay {
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                }
                .fixedSize()
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Right: ring + countdown

    private var ringPanel: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                ringTrack(size: size)
                ringFill(size: size)
                timeLabel
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func ringTrack(size: CGFloat) -> some View {
        Circle()
            .stroke(Color.white.opacity(0.08), lineWidth: size * 0.05)
    }

    private func ringFill(size: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: CGFloat(max(0, 1.0 - timerManager.progress)))
            .stroke(
                ringColor,
                style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 0.5), value: timerManager.progress)
    }

    private var timeLabel: some View {
        VStack(spacing: 2) {
            Text(formattedTime(timerManager.remainingTime))
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .foregroundColor(timeColor)
                .contentTransition(.numericText(countsDown: true))
                .animation(.smooth(duration: 0.3), value: timerManager.remainingTime)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if timerManager.state == .finished {
                Text("Done")
                    .font(.caption2)
                    .foregroundColor(.effectiveAccent)
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    // MARK: - Helpers

    private var timeColor: Color {
        timerManager.state == .finished ? .effectiveAccent : .white
    }

    private var ringColor: Color {
        switch timerManager.state {
        case .running:  return .effectiveAccent
        case .paused:   return .gray
        case .finished: return .effectiveAccent
        default:        return Color.white.opacity(0.25)
        }
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let total = Int(ceil(max(0, seconds)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
