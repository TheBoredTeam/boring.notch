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

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 22))
                .foregroundStyle(.gray)

            Text("Pomodoro Timer")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                durationPill(
                    icon: "target", label: "Focus", value: focusDuration / 60)
                durationPill(
                    icon: "cup.and.saucer", label: "Break",
                    value: shortBreakDuration / 60)
                durationPill(
                    icon: "cup.and.saucer.fill", label: "Long",
                    value: longBreakDuration / 60)
            }

            HStack(spacing: 12) {
                quickSetting(
                    icon: "target", current: focusDuration / 60,
                    options: [15, 25, 30, 45, 60]
                ) { val in
                    focusDuration = val * 60
                    pomodoroManager.remainingSeconds = val * 60
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
            .opacity(0.6)

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

    // MARK: - Active

    private var activeView: some View {
        VStack(spacing: 0) {
            Spacer()

            HStack(spacing: 6) {
                Image(systemName: pomodoroManager.phaseIcon)
                    .font(.system(size: 12))
                Text(pomodoroManager.phaseLabel)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(phaseColor.opacity(0.7))

            Text(pomodoroManager.formattedTime)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .opacity(pomodoroManager.isRunning ? 1 : 0.5)
                .padding(.vertical, 6)

            pomodoroProgress
                .padding(.horizontal, 24)

            if pomodoroManager.phase == .focus {
                Text(
                    "Session \(pomodoroManager.completedSessions + 1) of \(sessionsBeforeLongBreak)"
                )
                .font(.caption)
                .foregroundStyle(.gray.opacity(0.6))
                .padding(.top, 4)
            }

            Spacer()

            HStack(spacing: 0) {
                controlCapsule(icon: "backward.end.fill") {
                    pomodoroManager.skip()
                }

                controlCapsule(
                    icon: pomodoroManager.isRunning
                        ? "pause.fill" : "play.fill"
                ) {
                    if pomodoroManager.isRunning {
                        pomodoroManager.pause()
                    } else {
                        pomodoroManager.resume()
                    }
                }

                controlCapsule(icon: "arrow.counterclockwise") {
                    pomodoroManager.reset()
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Progress Bar

    private var pomodoroProgress: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(phaseColor.opacity(0.15))
                    .frame(height: 5)

                RoundedRectangle(cornerRadius: 2.5)
                    .fill(phaseColor)
                    .frame(
                        width: max(0, min(pomodoroManager.progress, 1))
                            * geometry.size.width,
                        height: 5
                    )
            }
        }
        .frame(height: 10)
    }

    // MARK: - Subviews

    private func durationPill(icon: String, label: String, value: Int)
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

    private func controlCapsule(
        icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .padding(.horizontal, 15)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundStyle(.white.opacity(0.8))
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
