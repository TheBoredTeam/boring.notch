//
//  PomodoroView.swift
//  boringNotch
//
//  Created by Claw on 2026-04-28.
//

import Defaults
import SwiftUI

struct PomodoroView: View {
    @ObservedObject var pomodoroManager = PomodoroManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        VStack(spacing: 16) {
            // Phase indicator
            HStack {
                ForEach([PomodoroManager.PomodoroPhase.work, .shortBreak, .longBreak], id: \.self) { phase in
                    Text(phase.rawValue)
                        .font(.caption)
                        .foregroundColor(pomodoroManager.currentPhase == phase ? .white : .gray)
                }
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
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 140, height: 140)

            // Controls
            HStack(spacing: 20) {
                Button(action: { pomodoroManager.stop() }) {
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

            // Session count
            HStack {
                Text("Sessions: \(pomodoroManager.sessionsCompleted)")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var phaseColor: Color {
        switch pomodoroManager.currentPhase {
        case .work: return .red
        case .shortBreak: return .green
        case .longBreak: return .blue
        }
    }
}
