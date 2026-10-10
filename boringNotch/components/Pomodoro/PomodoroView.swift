//
//  PomodoroView.swift
//  boringNotch
//
//  The Pomodoro tab shown in the open notch, plus the small countdown
//  shown on either side of the closed notch while a timer is active.
//

import Defaults
import SwiftUI

extension PomodoroPhase {
    var tint: Color {
        switch self {
        case .focus: return Color(red: 1.0, green: 0.36, blue: 0.32)
        case .shortBreak: return Color(red: 0.30, green: 0.85, blue: 0.50)
        case .longBreak: return Color(red: 0.35, green: 0.65, blue: 1.0)
        }
    }
}

// MARK: - Open notch tab

struct PomodoroView: View {
    @ObservedObject var pomodoro = PomodoroManager.shared

    private var tint: Color { pomodoro.phase.tint }

    var body: some View {
        HStack(spacing: 32) {
            progressRing
            VStack(alignment: .leading, spacing: 12) {
                phaseHeader
                sessionDots
                controls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 8)
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 8)
            Circle()
                .trim(from: 0, to: pomodoro.progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: pomodoro.progress)
            Text(pomodoro.formattedRemaining)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .accessibilityHidden(true)
        }
        .frame(width: 112, height: 112)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(String(localized: pomodoro.phase.title)), \(pomodoro.formattedRemaining)")
    }

    private var phaseHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: pomodoro.phase.icon)
                    .foregroundStyle(tint)
                Text(String(localized: pomodoro.phase.title))
                    .foregroundStyle(.white)
            }
            .font(.system(.title3, design: .rounded).weight(.semibold))

            Text(String(localized: statusText))
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }

    private var statusText: String {
        switch pomodoro.runState {
        case .idle: return "Ready when you are"
        case .running: return pomodoro.phase == .focus ? "Stay on one thing" : "Step away for a bit"
        case .paused: return "Paused"
        }
    }

    private var sessionDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<pomodoro.sessionsBeforeLongBreak, id: \.self) { index in
                Circle()
                    .fill(index < pomodoro.sessionsInCycle ? tint : Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
        }
        .animation(.smooth, value: pomodoro.sessionsInCycle)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            PomodoroControlButton(icon: "arrow.counterclockwise", accessibilityLabel: "Reset Pomodoro", size: 34) {
                pomodoro.reset()
            }
            PomodoroControlButton(
                icon: pomodoro.isRunning ? "pause.fill" : "play.fill",
                accessibilityLabel: pomodoro.isRunning ? "Pause Pomodoro" : "Start Pomodoro",
                size: 44,
                fill: tint,
                foreground: .black
            ) {
                pomodoro.toggle()
            }
            PomodoroControlButton(icon: "forward.end.fill", accessibilityLabel: "Skip to next Pomodoro phase", size: 34) {
                pomodoro.skip()
            }
        }
    }
}

private struct PomodoroControlButton: View {
    let icon: String
    let accessibilityLabel: LocalizedStringKey
    let size: CGFloat
    var fill: Color = Color.white.opacity(0.12)
    var foreground: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(fill)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(foreground)
                }
                .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Closed notch countdown

struct PomodoroLiveActivity: View {
    /// Width of the area on each side of the notch. Kept equal on both sides so the real notch stays centered.
    static let sideWidth: CGFloat = 52

    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var pomodoro = PomodoroManager.shared

    private var tint: Color { pomodoro.phase.tint }
    private var iconSize: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: pomodoro.progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: pomodoro.progress)
                Image(systemName: pomodoro.phase.icon)
                    .font(.system(size: iconSize * 0.4))
                    .foregroundStyle(tint)
            }
            .frame(width: iconSize, height: iconSize)
            .frame(width: Self.sideWidth)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Text(pomodoro.formattedRemaining)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(pomodoro.isRunning ? tint : Color.gray)
                .lineLimit(1)
                .frame(width: Self.sideWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pomodoro, \(String(localized: pomodoro.phase.title)), \(pomodoro.formattedRemaining)")
    }
}

#Preview {
    PomodoroView()
        .environmentObject(BoringViewModel())
        .frame(width: 560, height: 150)
        .background(.black)
}
