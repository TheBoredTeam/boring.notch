//
//  PomodoroView.swift
//  boringNotch
//
//  Created by Claw on 2026-04-28.
//  Modified to match NotchHomeView layout style.
//

import Defaults
import SwiftUI

struct PomodoroView: View {
    @ObservedObject var pomodoroManager = PomodoroManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            // Left spacer to match MusicPlayerView layout (album art section)
            Color.clear
                .frame(width: 60, height: 60)

            // Center timer content
            timerContent
                .frame(maxWidth: .infinity)

            // Right spacer for balance
            Color.clear
                .frame(width: 60, height: 60)
        }
        .padding(.horizontal, 10)
    }

    private var timerContent: some View {
        VStack(spacing: 6) {
            // Phase indicator + sessions + reset button
            HStack(spacing: 8) {
                ForEach([PomodoroManager.PomodoroPhase.work, .shortBreak, .longBreak], id: \.self) { phase in
                    Text(phase.rawValue)
                        .font(.system(size: 9))
                        .foregroundColor(pomodoroManager.currentPhase == phase ? .white : .gray)
                }

                // Sessions counter with reset capability
                Button(action: {
                    // Long press or double click to reset
                }) {
                    HStack(spacing: 2) {
                        Text("• \(pomodoroManager.sessionsCompleted)")
                            .font(.system(size: 9))
                            .foregroundStyle(.gray)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.8)
                        .onEnded { _ in
                            pomodoroManager.resetSessions()
                        }
                )

                Spacer()

                // Reset all button
                Button(action: {
                    pomodoroManager.resetAll()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Reset all")
            }

            // Circular progress + time
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: pomodoroManager.progress)
                    .stroke(
                        phaseColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: pomodoroManager.progress)

                VStack(spacing: 4) {
                    Text(pomodoroManager.currentPhase.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.gray)

                    Text(pomodoroManager.formattedTime)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 90, height: 90)

            // Controls
            HStack(spacing: 20) {
                Button(action: { pomodoroManager.pause() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    if pomodoroManager.isRunning {
                        pomodoroManager.pause()
                    } else {
                        pomodoroManager.start()
                    }
                }) {
                    Image(systemName: pomodoroManager.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { pomodoroManager.skip() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Helpers

    private var phaseColor: Color {
        switch pomodoroManager.currentPhase {
        case .work: return .red
        case .shortBreak: return .green
        case .longBreak: return .blue
        }
    }
}