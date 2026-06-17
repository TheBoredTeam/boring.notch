//
//  PomodoroView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct PomodoroView: View {
    @ObservedObject var pomodoro = PomodoroManager.shared
    @Default(.pomodoroWorkDuration) private var workMinutes
    @Default(.pomodoroCyclesBeforeLongBreak) private var cycles

    private let presets: [Int] = [15, 25, 45, 60]

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            ringTimer
            rightPanel
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Ring

    private var ringTimer: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 9)

            Circle()
                .trim(from: 0, to: pomodoro.progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [phaseColor.opacity(0.65), phaseColor]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: phaseColor.opacity(0.45), radius: 5)
                .animation(.linear(duration: 0.5), value: pomodoro.progress)

            VStack(spacing: 3) {
                Text(timeString)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text(pomodoro.phase.label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.8)
                    .foregroundColor(phaseColor)
            }
        }
        .frame(width: 124, height: 124)
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            roundRow
            controls
            presetSection
            Spacer(minLength: 0)
            statsRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Round indicator

    private var roundRow: some View {
        HStack(spacing: 7) {
            ForEach(0..<max(1, cycles), id: \.self) { index in
                Circle()
                    .fill(index < (pomodoro.completedPomodoros % max(1, cycles)) ? phaseColor : Color.white.opacity(0.16))
                    .frame(width: 7, height: 7)
            }
            Spacer()
            Text("Round \(pomodoro.completedPomodoros / max(1, cycles) + 1)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: { withAnimation(.snappy) { pomodoro.toggle() } }) {
                HStack(spacing: 7) {
                    Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(pomodoro.isRunning ? "Pause" : "Start")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.black)
                .frame(height: 34)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(phaseColor)
                        .shadow(color: phaseColor.opacity(0.4), radius: 4, y: 1)
                )
            }
            .buttonStyle(.plain)

            circleButton("arrow.counterclockwise") { pomodoro.reset() }
            circleButton("forward.end.fill") { pomodoro.skip() }
        }
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom time presets

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FOCUS LENGTH")
                .font(.system(size: 8.5, weight: .heavy))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.35))
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { minutes in
                    presetChip(minutes)
                }
            }
        }
    }

    private func presetChip(_ minutes: Int) -> some View {
        let active = Int(workMinutes) == minutes
        return Button {
            withAnimation(.snappy(duration: 0.2)) { workMinutes = Double(minutes) }
        } label: {
            Text("\(minutes)m")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(active ? .black : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(
                    Capsule().fill(active ? phaseColor : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9))
                .foregroundColor(phaseColor.opacity(0.8))
            Text("Today")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
            Text("\(focusTimeString(pomodoro.todayFocusSeconds))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text("·")
                .foregroundColor(.white.opacity(0.3))
            Text("\(pomodoro.todayPomodoros) sessions")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private func focusTimeString(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    // MARK: - Helpers

    private var phaseColor: Color {
        switch pomodoro.phase {
        case .work: return Color(red: 1, green: 0.42, blue: 0.42)
        case .shortBreak: return Color(red: 0.4, green: 0.85, blue: 0.6)
        case .longBreak: return Color(red: 0.42, green: 0.7, blue: 1)
        }
    }

    private var timeString: String {
        let total = Int(pomodoro.timeRemaining)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

struct PomodoroLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var pomodoroManager = PomodoroManager.shared

    var body: some View {
        HStack {
            // Left Side: Small Ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: pomodoroManager.progress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: pomodoroManager.progress)
            }
            .frame(
                width: max(0, vm.effectiveClosedNotchHeight - 12),
                height: max(0, vm.effectiveClosedNotchHeight - 12)
            )

            // Middle: Notch Space
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)

            // Right Side: Timer Text
            HStack {
                Text(timeString)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(phaseColor)
            }
            .frame(
                width: max(0, vm.effectiveClosedNotchHeight - 12 + 20),
                height: max(0, vm.effectiveClosedNotchHeight - 12),
                alignment: .center
            )
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var phaseColor: Color {
        switch pomodoroManager.phase {
        case .work: return Color(red: 1, green: 0.42, blue: 0.42)
        case .shortBreak: return Color(red: 0.4, green: 0.85, blue: 0.6)
        case .longBreak: return Color(red: 0.42, green: 0.7, blue: 1)
        }
    }

    private var timeString: String {
        let total = Int(pomodoroManager.timeRemaining)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

#Preview {
    PomodoroView()
        .frame(width: 580, height: 160)
        .background(.black)
}
