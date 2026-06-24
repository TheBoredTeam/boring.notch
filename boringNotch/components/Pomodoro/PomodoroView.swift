//
//  PomodoroView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct PomodoroView: View {
    @ObservedObject var pomodoroManager = PomodoroManager.shared
    @Default(.pomodoroFocusDuration) var focusDuration
    @Default(.pomodoroShortBreakDuration) var shortBreakDuration
    @Default(.pomodoroLongBreakDuration) var longBreakDuration
    @Default(.pomodoroSessionsBeforeLongBreak) var sessionsBeforeLongBreak

    var body: some View {
        if !pomodoroManager.isRunning
            && pomodoroManager.remainingSeconds == pomodoroManager.totalSeconds
        {
            idleView
        } else {
            activeView
        }
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 22))
                .foregroundStyle(.gray)

            Text("Pomodoro Timer")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                durationButton(
                    icon: "target", label: "Focus", value: focusDuration / 60)
                durationButton(
                    icon: "cup.and.saucer", label: "Break",
                    value: shortBreakDuration / 60)
                durationButton(
                    icon: "cup.and.saucer.fill", label: "Long",
                    value: longBreakDuration / 60)
            }

            Button(action: { pomodoroManager.start() }) {
                Text("Start Focus")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activeView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: pomodoroManager.phaseIcon)
                    .font(.system(size: 14))
                Text(pomodoroManager.phaseLabel)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(phaseColor.opacity(0.8))

            Text(pomodoroManager.formattedTime)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .opacity(pomodoroManager.isRunning ? 1 : 0.6)

            ProgressView(value: pomodoroManager.progress)
                .tint(phaseColor)
                .scaleEffect(x: 1, y: 1.5, anchor: .center)
                .padding(.horizontal, 40)

            if pomodoroManager.phase == .focus {
                Text(
                    "Session \(pomodoroManager.completedSessions + 1) of \(sessionsBeforeLongBreak) until long break"
                )
                .font(.caption)
                .foregroundStyle(.gray)
            }

            HStack(spacing: 20) {
                controlButton(icon: "backward.end.fill", label: "Skip") {
                    pomodoroManager.skip()
                }

                controlButton(
                    icon: pomodoroManager.isRunning ? "pause.fill" : "play.fill",
                    label: pomodoroManager.isRunning ? "Pause" : "Resume"
                ) {
                    if pomodoroManager.isRunning {
                        pomodoroManager.pause()
                    } else {
                        pomodoroManager.resume()
                    }
                }

                controlButton(icon: "arrow.counterclockwise", label: "Reset") {
                    pomodoroManager.reset()
                }
            }
            .padding(.top, 2)

            HStack(spacing: 12) {
                quickSetting(
                    icon: "target", current: focusDuration / 60,
                    options: [15, 25, 30, 45, 60]
                ) { val in
                    focusDuration = val * 60
                    if case .focus = pomodoroManager.phase,
                        !pomodoroManager.isRunning,
                        pomodoroManager.remainingSeconds
                            == pomodoroManager.totalSeconds
                    {
                        pomodoroManager.remainingSeconds = val * 60
                    }
                }
                quickSetting(
                    icon: "cup.and.saucer", current: shortBreakDuration / 60,
                    options: [3, 5, 10, 15]
                ) { val in
                    shortBreakDuration = val * 60
                }
                quickSetting(
                    icon: "cup.and.saucer.fill", current: longBreakDuration / 60,
                    options: [10, 15, 20, 30]
                ) { val in
                    longBreakDuration = val * 60
                }
            }
            .padding(.top, 2)
            .opacity(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func durationButton(icon: String, label: String, value: Int)
        -> some View
    {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text("\(value)m")
                .font(.caption2)
        }
        .foregroundStyle(.gray)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func controlButton(
        icon: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 50, height: 36)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func quickSetting(
        icon: String, current: Int, options: [Int],
        onChange: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
            ForEach(options, id: \.self) { val in
                Button(action: { onChange(val) }) {
                    Text("\(val)")
                        .font(
                            .system(
                                size: 9,
                                weight: val == current ? .bold : .regular)
                        )
                        .foregroundStyle(
                            val == current ? .white : .gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var phaseColor: Color {
        switch pomodoroManager.phase {
        case .focus: return Color.orange
        case .shortBreak: return Color.green
        case .longBreak: return Color.blue
        }
    }
}
