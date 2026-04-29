//
//  PomodoroView.swift
//  boringNotch
//
//  Created by Christian Teo on 2026-04-29.
//  Sized to match NotchHomeView layout style.
//

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
        VStack(spacing: 8) {
            // Phase indicator + sessions + reset button
            HStack(spacing: 12) {
                ForEach([PomodoroManager.PomodoroPhase.work, .shortBreak, .longBreak], id: \.self) { phase in
                    Text(phase.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(pomodoroManager.currentPhase == phase ? .white : .gray.opacity(0.6))
                }

                Spacer()

                // Sessions counter
                Text("• \(pomodoroManager.sessionsCompleted)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.8)
                            .onEnded { _ in
                                pomodoroManager.resetSessions()
                            }
                    )

                // Reset all button
                Button(action: {
                    pomodoroManager.reset()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Reset Timer")
            }

            // Circular progress + time
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: pomodoroManager.progress)
                    .stroke(
                        pomodoroManager.phaseColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: pomodoroManager.progress)

                VStack(spacing: 4) {
                    Text(pomodoroManager.currentPhase.displayName)
                        .font(.caption2)
                        .foregroundStyle(.gray)

                    Text(pomodoroManager.formattedTime)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 90, height: 90)

            // Controls
            HStack(spacing: 24) {
                // Reset button
                Button(action: {
                    pomodoroManager.reset()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Reset")

                // Play/Pause button
                Button(action: {
                    if pomodoroManager.isRunning {
                        pomodoroManager.pause()
                    } else {
                        pomodoroManager.start()
                    }
                }) {
                    Image(systemName: pomodoroManager.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(pomodoroManager.phaseColor.opacity(0.8))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .help(pomodoroManager.isRunning ? "Pause" : "Start")

                // Skip button
                Button(action: {
                    pomodoroManager.pause()
                    pomodoroManager.skip()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Skip to Next")
            }
        }
    }
}

// Compact view for closed notch state
struct PomodoroClosedView: View {
    @ObservedObject var pomodoroManager = PomodoroManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Mini progress circle
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
        .frame(width: 300, height: 300)
        .background(Color.black)
}
