//
//  PomodoroView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct PomodoroView: View {
    @ObservedObject var manager = PomodoroManager.shared
    @EnvironmentObject var vm: BoringViewModel

    private var phaseColor: Color {
        switch manager.phase {
        case .work:
            return Color.red
        case .shortBreak:
            return Color.green
        case .longBreak:
            return Color.blue
        }
    }

    private var formattedTime: String {
        let totalSeconds = max(0, Int(manager.timeRemaining))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            // Left: Large Circular Progress Ring & Digital Timer
            ZStack {
                // Background Ring Track
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 7)

                // Animated Gradient Progress Ring
                Circle()
                    .trim(from: 0, to: CGFloat(manager.progressRatio))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [phaseColor.opacity(0.7), phaseColor]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: manager.progressRatio)

                // Timer Digital Countdown & Phase Info
                VStack(spacing: 2) {
                    Text(formattedTime)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()

                    HStack(spacing: 4) {
                        Image(systemName: manager.phase.icon)
                            .font(.system(size: 10))
                        Text(manager.phaseDisplayName(for: manager.phase))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(phaseColor)
                }
            }
            .frame(width: 104, height: 104)

            // Right: Full-width Controls, Phase Bar & Analytics Cards
            VStack(alignment: .leading, spacing: 10) {
                // Row 1: Phase Selector Bar
                HStack(spacing: 8) {
                    ForEach(PomodoroPhase.allCases) { phase in
                        Button {
                            withAnimation(.smooth) {
                                manager.selectPhase(phase)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: phase.icon)
                                    .font(.system(size: 10))
                                Text(manager.phaseDisplayName(for: phase))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                manager.phase == phase
                                    ? phaseColor.opacity(0.22)
                                    : Color.white.opacity(0.06)
                            )
                            .foregroundStyle(
                                manager.phase == phase
                                    ? phaseColor
                                    : Color.gray
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(manager.phase == phase ? phaseColor.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Row 2: Play/Pause, Quick +5m/-5m Tweak Controls & Actions
                HStack(spacing: 12) {
                    // Reset Button
                    Button {
                        withAnimation(.smooth) {
                            manager.reset()
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset Timer")

                    // Play / Pause Main Button
                    Button {
                        withAnimation(.smooth) {
                            manager.togglePlayPause()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: manager.state == .running ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text(manager.state == .running ? "Pause" : (manager.state == .paused ? "Resume" : "Start"))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(phaseColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(color: phaseColor.opacity(0.4), radius: 5, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)

                    // Skip Button
                    Button {
                        withAnimation(.smooth) {
                            manager.skip()
                        }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Skip Phase")

                    // Power User Quick Adjustments: +5m / -5m
                    HStack(spacing: 4) {
                        Button("-5m") {
                            withAnimation(.smooth) {
                                manager.addMinutes(-5)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())

                        Button("+5m") {
                            withAnimation(.smooth) {
                                manager.addMinutes(5)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }

                    Spacer(minLength: 4)

                    // Settings Quick Button
                    Button {
                        DispatchQueue.main.async {
                            SettingsWindowController.shared.showWindow(selectedTab: .pomodoro)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 12))
                            Text("Customize")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Row 3: Full-width Stats & Progress Cards
                HStack(spacing: 10) {
                    // Stat 1: Completed Sessions vs Goal
                    HStack(spacing: 6) {
                        Text("🍅")
                            .font(.system(size: 12))
                        let target = Defaults[.pomodoroTargetSessions]
                        Text("Goal: \(manager.completedSessionsCount) / \(target) sessions")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Stat 2: Long Break Progress
                    HStack(spacing: 6) {
                        Image(systemName: "cup.and.saucer")
                            .font(.system(size: 10))
                            .foregroundStyle(.gray)
                        let interval = max(1, Defaults[.pomodoroLongBreakInterval])
                        let rem = manager.completedSessionsCount % interval
                        let sessionsUntilLong = interval - rem
                        Text("Next Long Break: in \(sessionsUntilLong) session\(sessionsUntilLong == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.gray)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
