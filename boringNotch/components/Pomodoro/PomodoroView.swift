//
//  PomodoroView.swift
//  boringNotch
//
//  Open-notch tab and closed-notch live activity for the focus timer.
//

import Defaults
import SwiftUI

struct PomodoroRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
    }
}

struct PomodoroView: View {
    @ObservedObject var pomodoro = PomodoroManager.shared
    @Default(.pomodoroSessionsBeforeLongBreak) var sessionsBeforeLongBreak

    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                PomodoroRing(progress: pomodoro.progress, tint: pomodoro.phase.tint, lineWidth: 9)
                VStack(spacing: 2) {
                    Text(pomodoro.formattedRemaining)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.smooth, value: pomodoro.formattedRemaining)
                    Text(pomodoro.isRunning ? "Running" : (pomodoro.isActive ? "Paused" : "Ready"))
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 12) {
                Label(pomodoro.phase.title, systemImage: pomodoro.phase.icon)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(pomodoro.phase.tint)
                    .contentTransition(.opacity)

                sessionDots

                HStack(spacing: 10) {
                    controlButton(icon: "arrow.counterclockwise", help: "Reset") {
                        pomodoro.reset()
                    }
                    .disabled(!pomodoro.isActive && pomodoro.phase == .focus && pomodoro.completedFocusSessions == 0)

                    controlButton(icon: pomodoro.isRunning ? "pause.fill" : "play.fill", help: pomodoro.isRunning ? "Pause" : "Start", prominent: true) {
                        pomodoro.toggle()
                    }

                    controlButton(icon: "forward.end.fill", help: "Skip to next phase") {
                        pomodoro.skip()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionDots: some View {
        let total = max(1, sessionsBeforeLongBreak)
        return HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < pomodoro.completedFocusSessions ? PomodoroPhase.focus.tint : Color.white.opacity(0.15))
                    .frame(width: 7, height: 7)
            }
            Text("\(min(pomodoro.completedFocusSessions, total))/\(total)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.gray)
        }
    }

    private func controlButton(icon: String, help: LocalizedStringKey, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 18 : 14, weight: .semibold))
                .foregroundStyle(prominent ? .black : .white)
                .frame(width: prominent ? 44 : 34, height: prominent ? 44 : 34)
                .background(Circle().fill(prominent ? Color.white : Color.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Compact countdown shown on both sides of the closed notch.
struct PomodoroLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var pomodoro = PomodoroManager.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    static let sideWidth: CGFloat = 44
    static let announcementWidth: CGFloat = 96

    private var isAnnouncing: Bool {
        coordinator.expandingView.show && coordinator.expandingView.type == .pomodoro
    }

    var body: some View {
        let iconSize = max(0, vm.effectiveClosedNotchHeight - 12)
        HStack {
            ZStack {
                PomodoroRing(progress: pomodoro.progress, tint: pomodoro.phase.tint, lineWidth: 2.5)
                Image(systemName: pomodoro.phase.icon)
                    .font(.system(size: iconSize * 0.42, weight: .semibold))
                    .foregroundStyle(pomodoro.phase.tint)
            }
            .frame(width: iconSize, height: iconSize)
            .frame(width: Self.sideWidth, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 4 + 2 * liveActivityEdgeMargin)

            Group {
                if isAnnouncing {
                    Text(pomodoro.phase.title)
                        .foregroundStyle(pomodoro.phase.tint)
                        .lineLimit(1)
                        .transition(.blurReplace)
                } else {
                    Text(pomodoro.formattedRemaining)
                        .monospacedDigit()
                        .foregroundStyle(pomodoro.isRunning ? .white : .gray)
                        .contentTransition(.numericText(countsDown: true))
                        .transition(.blurReplace)
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(width: isAnnouncing ? Self.announcementWidth : Self.sideWidth, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .animation(.smooth, value: isAnnouncing)
        .animation(.smooth, value: pomodoro.formattedRemaining)
    }
}
