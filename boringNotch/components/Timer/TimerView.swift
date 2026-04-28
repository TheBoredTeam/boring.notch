//
//  TimerView.swift
//  boringNotch
//

import SwiftUI

struct TimerView: View {
    @ObservedObject var timerManager = TimerManager.shared
    @EnvironmentObject var vm: BoringViewModel

    private let presets: [(label: String, seconds: TimeInterval)] = [
        ("1m", 60),
        ("5m", 300),
        ("10m", 600),
        ("15m", 900),
        ("30m", 1800),
    ]

    var body: some View {
        HStack(spacing: 20) {
            timeDisplay
            controls
        }
        .padding(.horizontal, 12)
        .transition(.opacity)
    }

    // MARK: - Left: Time Display

    private var timeDisplay: some View {
        ZStack {
            progressRing
            VStack(spacing: 2) {
                Text(formattedTime(timerManager.remainingTime))
                    .font(.system(size: 38, weight: .semibold, design: .monospaced))
                    .foregroundColor(timeColor)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.smooth(duration: 0.4), value: timerManager.remainingTime)

                if timerManager.state == .finished {
                    Text("Done")
                        .font(.caption)
                        .foregroundColor(.effectiveAccent)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .frame(width: 130, height: 130)
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0, CGFloat(1.0 - timerManager.progress)))
                .stroke(
                    timerManager.state == .finished ? Color.effectiveAccent : ringColor,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: timerManager.progress)
        }
    }

    // MARK: - Right: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if timerManager.state == .idle {
                presetRow
            }
            actionButtons
        }
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(presets, id: \.label) { preset in
                Button {
                    withAnimation(.smooth) {
                        timerManager.setDuration(preset.seconds)
                    }
                } label: {
                    Text(preset.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(timerManager.totalDuration == preset.seconds ? .white : .gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(timerManager.totalDuration == preset.seconds
                                      ? Color(nsColor: .secondarySystemFill)
                                      : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            switch timerManager.state {
            case .idle:
                adjustButton(delta: -60, icon: "minus")
                mainActionButton
                adjustButton(delta: 60, icon: "plus")

            case .running:
                mainActionButton
                resetButton
                adjustButton(delta: 60, icon: "plus.circle")

            case .paused:
                mainActionButton
                resetButton

            case .finished:
                resetButton
            }
        }
    }

    private var mainActionButton: some View {
        Button {
            withAnimation(.smooth) {
                switch timerManager.state {
                case .idle, .paused:
                    timerManager.start()
                case .running:
                    timerManager.pause()
                case .finished:
                    break
                }
            }
        } label: {
            Capsule()
                .fill(Color(nsColor: .secondarySystemFill))
                .frame(width: 54, height: 30)
                .overlay {
                    Image(systemName: mainActionIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var resetButton: some View {
        HoverButton(icon: "arrow.counterclockwise", scale: .medium) {
            withAnimation(.smooth) {
                timerManager.reset()
            }
        }
    }

    private func adjustButton(delta: TimeInterval, icon: String) -> some View {
        HoverButton(icon: icon, scale: .medium) {
            withAnimation(.smooth) {
                timerManager.adjustTime(by: delta)
            }
        }
    }

    // MARK: - Helpers

    private var mainActionIcon: String {
        switch timerManager.state {
        case .idle, .paused: return "play.fill"
        case .running: return "pause.fill"
        case .finished: return "play.fill"
        }
    }

    private var timeColor: Color {
        switch timerManager.state {
        case .finished: return .effectiveAccent
        case .running: return .white
        default: return .white.opacity(0.9)
        }
    }

    private var ringColor: Color {
        switch timerManager.state {
        case .running: return .effectiveAccent
        case .paused: return .gray
        default: return Color.white.opacity(0.3)
        }
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let total = Int(ceil(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
