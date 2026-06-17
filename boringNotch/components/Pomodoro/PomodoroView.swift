//
//  PomodoroView.swift
//  boringNotch
//

import SwiftUI

struct PomodoroView: View {
    @ObservedObject var pomodoro = PomodoroManager.shared

    var body: some View {
        HStack(spacing: 16) {
            ringTimer
            VStack(alignment: .leading, spacing: 6) {
                phaseLabel
                controls
                tomatoRow
                statsRow
            }
        }
        .padding(.vertical, 8)
        .transition(.opacity)
    }

    // MARK: - Ring

    private var ringTimer: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 5)

            Circle()
                .trim(from: 0, to: pomodoro.progress)
                .stroke(
                    phaseColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: pomodoro.progress)

            Text(timeString)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(width: 68, height: 68)
    }

    // MARK: - Phase label

    private var phaseLabel: some View {
        Text(pomodoro.phase.label)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(phaseColor)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: { pomodoro.toggle() }) {
                Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: { pomodoro.reset() }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: { pomodoro.skip() }) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Tomato counter

    private var tomatoRow: some View {
        HStack(spacing: 3) {
            ForEach(0..<4) { index in
                Text(index < (pomodoro.completedPomodoros % 4) ? "🍅" : "○")
                    .font(.system(size: 10))
            }
            if pomodoro.completedPomodoros >= 4 {
                Text("×\(pomodoro.completedPomodoros / 4)")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.4))
            Text("Today \(focusTimeString(pomodoro.todayFocusSeconds)) · \(pomodoro.todayPomodoros) 🍅")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.5))
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
        case .work: return Color(red: 1, green: 0.35, blue: 0.35)
        case .shortBreak: return Color(red: 0.35, green: 0.85, blue: 0.55)
        case .longBreak: return Color(red: 0.35, green: 0.65, blue: 1)
        }
    }

    private var timeString: String {
        let total = Int(pomodoro.timeRemaining)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

#Preview {
    PomodoroView()
        .frame(width: 300, height: 100)
        .background(.black)
}
