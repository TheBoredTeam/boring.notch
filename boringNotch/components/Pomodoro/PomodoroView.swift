//
//  PomodoroView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct PomodoroView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var pomodoro = PomodoroManager.shared
    @Default(.pomodoroWorkDuration) private var workMinutes
    @Default(.pomodoroCyclesBeforeLongBreak) private var cycles

    private let presets: [Int] = [15, 25, 45, 60]

    // The open notch is a fixed height; subtract the tab-bar strip, the panel's
    // bottom padding, and VStack spacing to get the height this page actually
    // gets. Sizing the ring from this keeps the layout inside the notch on any
    // Mac instead of relying on hard-coded numbers.
    private var ringSize: CGFloat {
        let header = max(24, vm.effectiveClosedNotchHeight)
        // Reserve room for the ambient-sound strip (24) + VStack spacing (6) too.
        let available = openNotchSize.height - header - 12 - 10 - 16 - 30
        return max(80, min(100, available))
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 20) {
                ringTimer
                rightPanel
            }
            AmbientSoundBar(accent: phaseColor)
                .frame(height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.smooth(duration: 0.4), value: pomodoro.phase)
    }

    // MARK: - Ring

    private var ringTimer: some View {
        let lineWidth: CGFloat = 9
        let tipRadius = ringSize / 2 - lineWidth / 2
        let tipAngle = Double(-90 + pomodoro.progress * 360) * .pi / 180

        return ZStack {
            // Soft phase-colored glow that gently breathes while running.
            TimelineView(.animation(paused: !pomodoro.isRunning)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let pulse = pomodoro.isRunning ? (sin(t * 1.7) + 1) / 2 : 0.5
                Circle()
                    .fill(phaseColor)
                    .blur(radius: 22 + CGFloat(pulse) * 10)
                    .opacity(0.18 + pulse * 0.16)
                    .padding(10)
            }

            // Track with a faint inner depth.
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: lineWidth)
            Circle()
                .stroke(Color.black.opacity(0.25), lineWidth: 1)
                .padding(lineWidth / 2)

            // Progress arc.
            Circle()
                .trim(from: 0, to: pomodoro.progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [phaseColor.opacity(0.55), phaseColor]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: phaseColor.opacity(0.45), radius: 5)
                .animation(.linear(duration: 0.5), value: pomodoro.progress)

            // Glowing dot riding the leading edge of the progress arc.
            if pomodoro.progress > 0.001 {
                Circle()
                    .fill(.white)
                    .frame(width: lineWidth - 2, height: lineWidth - 2)
                    .shadow(color: phaseColor, radius: 5)
                    .offset(x: cos(tipAngle) * tipRadius, y: sin(tipAngle) * tipRadius)
                    .animation(.linear(duration: 0.5), value: pomodoro.progress)
            }

            VStack(spacing: 3) {
                Text(timeString)
                    .font(.system(size: ringSize * 0.24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.3), value: timeString)
                Text(pomodoro.phase.label.uppercased())
                    .font(.system(size: 8.5, weight: .heavy))
                    .tracking(1.6)
                    .foregroundColor(phaseColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(phaseColor.opacity(0.12)))
            }
        }
        .frame(width: ringSize, height: ringSize)
        .scaleEffect(pomodoro.phase == .work ? 1.0 : 1.02)
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            roundRow
            controls
            presetSection
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Round indicator + today's stats (single line to save height)

    private var roundRow: some View {
        HStack(spacing: 7) {
            ForEach(0..<max(1, cycles), id: \.self) { index in
                Circle()
                    .fill(index < (pomodoro.completedPomodoros % max(1, cycles)) ? phaseColor : Color.white.opacity(0.16))
                    .frame(width: 7, height: 7)
            }
            Spacer()
            Image(systemName: "flame.fill")
                .font(.system(size: 9))
                .foregroundColor(phaseColor.opacity(0.8))
            Text(focusTimeString(pomodoro.todayFocusSeconds))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text("·")
                .foregroundColor(.white.opacity(0.3))
            Text("\(pomodoro.todayPomodoros)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: { withAnimation(.snappy) { pomodoro.toggle() } }) {
                HStack(spacing: 7) {
                    Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(pomodoro.isRunning ? "Pause" : "Start")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.black)
                .frame(height: 32)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [phaseColor, phaseColor.opacity(0.78)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                        .shadow(color: phaseColor.opacity(0.45), radius: 5, y: 1)
                )
            }
            .buttonStyle(PressableStyle())

            circleButton("arrow.counterclockwise") { pomodoro.reset() }
            circleButton("forward.end.fill") { pomodoro.skip() }
        }
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                )
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Custom time presets

    private var presetSection: some View {
        HStack(spacing: 6) {
            ForEach(presets, id: \.self) { minutes in
                presetChip(minutes)
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
                    Capsule()
                        .fill(active ? phaseColor : Color.white.opacity(0.08))
                        .overlay(
                            active ? Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5) : nil
                        )
                )
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Stats

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

/// Subtle tactile press feedback for the Pomodoro controls.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
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
        .environmentObject(BoringViewModel())
        .frame(width: 580, height: 160)
        .background(.black)
}
