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
        VStack(alignment: .center, spacing: 0) {
            // Timer circle on the left (matching album art position)
            timerCircleView
                .padding(.all, 5)

            // Control buttons on the right side (same pattern as slotToolbar in MusicControlsView)
            controlsView
                .drawingGroup()
                .compositingGroup()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 60)
    }

    // Timer circle on the left (matching album art position)
    private var timerCircleView: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 4)

            Circle()
                .trim(from: 0, to: pomodoroManager.progress)
                .stroke(
                    pomodoroManager.phaseColor,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: pomodoroManager.progress)

            Image(systemName: pomodoroManager.isRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: 50, height: 50)
    }

    // Controls on the right (same pattern as MusicControlsView)
    private var controlsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Phase indicator + sessions info
            phaseIndicatorView

            // Time display
            Text(pomodoroManager.formattedTime)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            // Control buttons (same horizontal layout as slotToolbar)
            HStack(spacing: 16) {
                // Reset button
                Button(action: {
                    pomodoroManager.resetAll()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())

                // Play/Pause button (main action)
                Button(action: {
                    if pomodoroManager.isRunning {
                        pomodoroManager.pause()
                    } else {
                        pomodoroManager.start()
                    }
                }) {
                    Image(systemName: pomodoroManager.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(pomodoroManager.phaseColor.opacity(0.8))
                        )
                }
                .buttonStyle(PlainButtonStyle())

                // Skip button
                Button(action: {
                    pomodoroManager.pause()
                    pomodoroManager.skip()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.leading, 5)
    }

    private var phaseIndicatorView: some View {
        HStack(spacing: 8) {
            ForEach([PomodoroManager.PomodoroPhase.work, .shortBreak, .longBreak], id: \.self) { phase in
                Text(phase.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(pomodoroManager.currentPhase == phase ? .white : .gray.opacity(0.6))
            }

            Spacer()

            // Sessions counter (tap to reset)
            Text("\(pomodoroManager.sessionsCompleted)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(sessionsColor)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.8)
                        .onEnded { _ in
                            pomodoroManager.resetSessions()
                        }
                )
                .help("Sessions completed. Long press to reset.")

            // Reset all button
            Button(action: {
                pomodoroManager.resetAll()
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Reset Everything")
        }
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