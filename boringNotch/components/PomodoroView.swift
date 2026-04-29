//
//  PomodoroView.swift
//  boringNotch
//
//  Created by Christian Teo on 2026-04-29.
//  Sized to match NotchHomeView layout style (same as MusicPlayerView/ShelfView).
//

import SwiftUI

struct PomodoroView: View {
    @ObservedObject var pomodoroManager = PomodoroManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        HStack {
            // LEFT: Timer content
            VStack(spacing: 4) {
                // Phase indicators
                phaseIndicators
                
                // Timer circle with progress ring
                timerCircleView
                
                // Sessions counter
                sessionsCounter
            }
            .frame(width: 110)

            Spacer()

            // RIGHT: Controls
            VStack(spacing: 8) {
                // Play/Pause button (main action)
                playPauseButton

                // Skip button
                skipButton

                // Reset button
                resetButton
            }
            .frame(width: 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    // MARK: - Timer Circle (Left side)

    private var timerCircleView: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 4)

            // Progress ring
            Circle()
                .trim(from: 0, to: pomodoroManager.progress)
                .stroke(
                    pomodoroManager.phaseColor,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: pomodoroManager.progress)

            // Time display inside circle
            Text(pomodoroManager.formattedTime)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(width: 70, height: 70)
    }

    // MARK: - Phase Indicators

    private var phaseIndicators: some View {
        HStack(spacing: 4) {
            ForEach([PomodoroManager.PomodoroPhase.work, .shortBreak, .longBreak], id: \.self) { phase in
                Text(abbreviatedPhaseName(phase))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(pomodoroManager.currentPhase == phase ? .white : .gray.opacity(0.5))
            }
        }
    }

    private func abbreviatedPhaseName(_ phase: PomodoroManager.PomodoroPhase) -> String {
        switch phase {
        case .work: return "W"
        case .shortBreak: return "SB"
        case .longBreak: return "LB"
        }
    }

    // MARK: - Sessions Counter

    private var sessionsCounter: some View {
        HStack(spacing: 2) {
            Text("•")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(sessionsColor)

            Text("\(pomodoroManager.sessionsCompleted)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(sessionsColor)
        }
        .help("Sessions completed. Long press to reset.")
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.8)
                .onEnded { _ in
                    pomodoroManager.resetSessions()
                }
        )
    }

    private var sessionsColor: Color {
        if pomodoroManager.sessionsCompleted % pomodoroManager.sessionsBeforeLongBreak == 0 && pomodoroManager.sessionsCompleted > 0 {
            return .blue
        } else if pomodoroManager.currentPhase == .work {
            return .red
        } else {
            return .green
        }
    }

    // MARK: - Control Buttons (Right side)

    private var playPauseButton: some View {
        Button(action: {
            if pomodoroManager.isRunning {
                pomodoroManager.pause()
            } else {
                pomodoroManager.start()
            }
        }) {
            Image(systemName: pomodoroManager.isRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(pomodoroManager.phaseColor.opacity(0.8))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var skipButton: some View {
        Button(action: {
            pomodoroManager.pause()
            pomodoroManager.skip()
        }) {
            Image(systemName: "forward.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var resetButton: some View {
        Button(action: {
            pomodoroManager.resetAll()
        }) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help("Reset timer")
    }
}

// MARK: - Compact view for closed notch state

struct PomodoroClosedView: View {
    @ObservedObject var pomodoroManager = PomodoroManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Mini progress circle (matching size pattern from other closed views)
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)

                Circle()
                    .trim(from: 0, to: pomodoroManager.progress)
                    .stroke(
                        pomodoroManager.phaseColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Image(systemName: pomodoroManager.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: max(0, vm.effectiveClosedNotchHeight - 16), height: max(0, vm.effectiveClosedNotchHeight - 16))

            // Timer info
            VStack(alignment: .leading, spacing: 2) {
                Text(pomodoroManager.formattedTime)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                Text(pomodoroManager.currentPhase.displayName)
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
            }

            Spacer()

            // Session indicator
            Text("\(pomodoroManager.sessionsCompleted)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(sessionsColor)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var sessionsColor: Color {
        if pomodoroManager.sessionsCompleted % pomodoroManager.sessionsBeforeLongBreak == 0 && pomodoroManager.sessionsCompleted > 0 {
            return .blue
        } else if pomodoroManager.currentPhase == .work {
            return .red
        } else {
            return .green
        }
    }
}

#Preview {
    PomodoroView()
        .frame(width: 300, height: 100)
        .background(Color.black)
}
