//
//  TimerView.swift
//  boringNotch
//
//  Created by Claude on 2026-07-05.
//

import Defaults
import SwiftUI

struct TimerView: View {
    @ObservedObject var timerManager = TimerManager.shared
    @Default(.pomodoroWorkMinutes) var workMinutes
    @Default(.pomodoroShortBreakMinutes) var shortBreakMinutes
    @State private var customMinutes: Double = 10

    var body: some View {
        Group {
            if timerManager.isTimerActive {
                activeTimer
            } else {
                timerSetup
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth, value: timerManager.isTimerActive)
    }

    // MARK: - Active state

    private var activeTimer: some View {
        HStack(spacing: 24) {
            ZStack {
                CircularProgressView(
                    progress: timerManager.progress,
                    color: modeColor
                )
                VStack(spacing: 2) {
                    Text(timerManager.formattedRemainingTime)
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.white)
                    Text(modeLabel)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
            .frame(width: 90, height: 90)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    HoverButton(icon: timerManager.isPaused ? "play.fill" : "pause.fill") {
                        if timerManager.isPaused {
                            timerManager.resume()
                        } else {
                            timerManager.pause()
                        }
                    }
                    HoverButton(icon: "stop.fill") {
                        timerManager.stop()
                    }
                    if timerManager.mode.isPomodoro {
                        HoverButton(icon: "forward.end.fill") {
                            timerManager.skipPhase()
                        }
                    }
                }

                if timerManager.mode.isPomodoro {
                    HStack(spacing: 4) {
                        ForEach(0..<sessionsPerCycle, id: \.self) { index in
                            Circle()
                                .fill(index < filledSessionDots ? Color.effectiveAccent : Color.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Setup state

    private var timerSetup: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                presetButton(label: String(localized: "Pomodoro"), icon: "timer") {
                    timerManager.startPomodoro()
                }
                presetButton(label: "5:00", icon: nil) {
                    timerManager.start(durationMinutes: 5)
                }
                presetButton(label: "10:00", icon: nil) {
                    timerManager.start(durationMinutes: 10)
                }
                presetButton(label: "25:00", icon: nil) {
                    timerManager.start(durationMinutes: 25)
                }
            }

            HStack(spacing: 10) {
                Slider(value: $customMinutes, in: 1...120, step: 1)
                    .frame(width: 180)
                    .tint(Color.effectiveAccent)
                Text("\(Int(customMinutes)) min")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.gray)
                    .frame(width: 52, alignment: .leading)
                presetButton(label: String(localized: "Start"), icon: "play.fill") {
                    timerManager.start(durationMinutes: Int(customMinutes))
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func presetButton(label: String, icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color(nsColor: .secondarySystemFill), in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var sessionsPerCycle: Int {
        max(1, Defaults[.pomodoroSessionsBeforeLongBreak])
    }

    private var filledSessionDots: Int {
        let completed = timerManager.completedSessions
        guard completed > 0 else { return 0 }
        let remainder = completed % sessionsPerCycle
        return remainder == 0 ? sessionsPerCycle : remainder
    }

    private var modeColor: Color {
        switch timerManager.mode {
        case .shortBreak, .longBreak:
            return .green
        default:
            return .effectiveAccent
        }
    }

    private var modeLabel: String {
        switch timerManager.mode {
        case .work:
            return String(localized: "Focus")
        case .shortBreak:
            return String(localized: "Short break")
        case .longBreak:
            return String(localized: "Long break")
        case .custom:
            return String(localized: "Timer")
        }
    }
}

#Preview {
    TimerView()
        .frame(width: 500, height: 160)
        .background(.black)
}
