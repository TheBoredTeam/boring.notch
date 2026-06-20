//
//  PomodoroView.swift
//  boringNotch
//

import Defaults
import SwiftUI

@MainActor
final class PomodoroTimerModel: ObservableObject {
    static let shared = PomodoroTimerModel()

    enum Phase: Equatable {
        case idle
        case work
        case breakTime
        case complete
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isRunning = false
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var completedFocusSessions: Int = 0
    @Published private(set) var workMinutes: Int
    @Published private(set) var breakMinutes: Int

    private var timer: Timer?
    private var totalSecondsForCurrentPhase: Int

    private init() {
        let initialWorkMinutes = PomodoroTimerModel.sanitizedMinutes(Defaults[.pomodoroWorkMinutes])
        workMinutes = initialWorkMinutes
        breakMinutes = PomodoroTimerModel.sanitizedMinutes(Defaults[.pomodoroBreakMinutes], range: 1...60)
        let initialSeconds = initialWorkMinutes * 60
        remainingSeconds = initialSeconds
        totalSecondsForCurrentPhase = initialSeconds
    }

    func setWorkMinutes(_ newValue: Int) {
        workMinutes = PomodoroTimerModel.sanitizedMinutes(newValue)
        Defaults[.pomodoroWorkMinutes] = workMinutes
        if phase == .idle || phase == .work, !isRunning {
            reset(to: .work)
        }
    }

    func setBreakMinutes(_ newValue: Int) {
        breakMinutes = PomodoroTimerModel.sanitizedMinutes(newValue, range: 1...60)
        Defaults[.pomodoroBreakMinutes] = breakMinutes
        if phase == .breakTime, !isRunning {
            reset(to: .breakTime)
        }
    }

    var progress: Double {
        guard totalSecondsForCurrentPhase > 0 else { return 0 }
        let elapsed = Double(totalSecondsForCurrentPhase - remainingSeconds)
        return min(max(elapsed / Double(totalSecondsForCurrentPhase), 0), 1)
    }

    var timeDisplay: String {
        let minutes = max(remainingSeconds, 0) / 60
        let seconds = max(remainingSeconds, 0) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var phaseTitle: String {
        switch phase {
        case .idle: return "Ready to focus"
        case .work: return isRunning ? "Focus in progress" : "Focus paused"
        case .breakTime: return isRunning ? "Break in motion" : "Break paused"
        case .complete: return "Session complete"
        }
    }

    var phaseSubtitle: String {
        switch phase {
        case .idle: return "Set a calm pace and start when you are ready."
        case .work: return "One task. No context switching."
        case .breakTime: return "Breathe, stretch, look away from the screen."
        case .complete: return "Nice work. Start another round when ready."
        }
    }

    var closedNotchLabel: String {
        switch phase {
        case .idle: return "Pomodoro"
        case .work: return isRunning ? "Focus" : "Paused"
        case .breakTime: return isRunning ? "Break" : "Paused"
        case .complete: return "Done"
        }
    }

    var closedNotchIcon: String {
        switch phase {
        case .idle: return "timer"
        case .work: return isRunning ? "flame.fill" : "pause.fill"
        case .breakTime: return isRunning ? "leaf.fill" : "pause.fill"
        case .complete: return "checkmark.seal.fill"
        }
    }

    var shouldShowClosedCountdown: Bool {
        phase != .idle
    }

    var accent: Color {
        switch phase {
        case .idle: return Color(red: 0.58, green: 0.70, blue: 1.0)
        case .work: return Color(red: 1.0, green: 0.36, blue: 0.42)
        case .breakTime: return Color(red: 0.30, green: 0.88, blue: 0.68)
        case .complete: return Color(red: 1.0, green: 0.78, blue: 0.30)
        }
    }

    var primaryButtonTitle: String {
        if isRunning { return "Pause" }
        switch phase {
        case .idle, .complete: return "Start"
        case .work, .breakTime: return "Resume"
        }
    }

    var primaryButtonIcon: String {
        isRunning ? "pause.fill" : "play.fill"
    }

    func togglePrimaryAction() {
        isRunning ? pause() : start()
    }

    func start() {
        if phase == .idle || phase == .complete {
            begin(.work)
        }
        isRunning = true
        startTimerIfNeeded()
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func resetToIdle() {
        pause()
        phase = .idle
        remainingSeconds = workMinutes * 60
        totalSecondsForCurrentPhase = remainingSeconds
    }

    func skipPhase() {
        switch phase {
        case .idle:
            begin(.breakTime)
        case .work:
            completeWorkPhase()
        case .breakTime, .complete:
            begin(.work)
        }
        isRunning = true
        startTimerIfNeeded()
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isRunning else { return }
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            advancePhase()
        }
    }

    private func advancePhase() {
        switch phase {
        case .work:
            completeWorkPhase()
        case .breakTime:
            completedFocusSessions += 1
            begin(.complete)
            isRunning = false
            timer?.invalidate()
            timer = nil
        case .idle, .complete:
            begin(.work)
        }
    }

    private func completeWorkPhase() {
        begin(.breakTime)
    }

    private func begin(_ newPhase: Phase) {
        phase = newPhase
        switch newPhase {
        case .idle, .work:
            remainingSeconds = workMinutes * 60
        case .breakTime:
            remainingSeconds = breakMinutes * 60
        case .complete:
            remainingSeconds = 0
        }
        totalSecondsForCurrentPhase = max(remainingSeconds, 1)
    }

    private func reset(to newPhase: Phase) {
        begin(newPhase)
        isRunning = false
    }

    private static func sanitizedMinutes(_ value: Int, range: ClosedRange<Int> = 1...180) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct PomodoroView: View {
    @ObservedObject private var timer = PomodoroTimerModel.shared
    @State private var glowPulse = false

    var body: some View {
        HStack(spacing: 14) {
            timerDial
                .frame(width: 118, height: 118)

            VStack(alignment: .leading, spacing: 10) {
                header
                settingsStrip
                controls
            }
            .frame(width: 300, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(backgroundGlow)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 10)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: phaseIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(timer.accent)
                Text(timer.phaseTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text("#\(timer.completedFocusSessions + 1)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: Capsule())
            }

            Text(timer.phaseSubtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
        }
    }

    private var timerDial: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [timer.accent.opacity(0.30), .black.opacity(0.35), .black.opacity(0.78)],
                        center: .center,
                        startRadius: 8,
                        endRadius: 72
                    )
                )
                .shadow(color: timer.accent.opacity(glowPulse && timer.isRunning ? 0.42 : 0.20), radius: glowPulse && timer.isRunning ? 22 : 12)

            Circle()
                .stroke(.white.opacity(0.09), lineWidth: 9)

            Circle()
                .trim(from: 0, to: max(timer.progress, timer.phase == .complete ? 1 : 0.018))
                .stroke(
                    AngularGradient(
                        colors: [timer.accent.opacity(0.55), timer.accent, .white.opacity(0.92), timer.accent.opacity(0.55)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.35), value: timer.progress)

            VStack(spacing: 2) {
                Text(timer.timeDisplay)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(phaseLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(timer.accent.opacity(0.88))
            }
        }
    }

    private var settingsStrip: some View {
        HStack(spacing: 8) {
            minuteStepper(title: "Focus", value: timer.workMinutes, range: 1...180) { timer.setWorkMinutes($0) }
            minuteStepper(title: "Break", value: timer.breakMinutes, range: 1...60) { timer.setBreakMinutes($0) }
        }
    }

    private func minuteStepper(title: String, value: Int, range: ClosedRange<Int>, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Text("\(value)m")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .monospacedDigit()
            }
            Spacer(minLength: 2)
            Stepper("", value: Binding(
                get: { value },
                set: { onChange(min(max($0, range.lowerBound), range.upperBound)) }
            ), in: range)
            .labelsHidden()
            .controlSize(.mini)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: timer.togglePrimaryAction) {
                Label(timer.primaryButtonTitle, systemImage: timer.primaryButtonIcon)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .frame(width: 112, height: 30)
                    .foregroundStyle(.black.opacity(0.82))
                    .background(timer.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .shadow(color: timer.accent.opacity(0.34), radius: 10, y: 4)

            Button(action: timer.skipPhase) {
                Label(skipTitle, systemImage: "forward.end.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(width: 86, height: 30)
                    .foregroundStyle(.white.opacity(0.82))
                    .background(.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: timer.resetToIdle) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 32, height: 30)
                    .foregroundStyle(.white.opacity(0.72))
                    .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var backgroundGlow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.black.opacity(0.35))
            LinearGradient(
                colors: [timer.accent.opacity(0.20), .white.opacity(0.035), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var phaseIcon: String {
        switch timer.phase {
        case .idle: return "sparkles"
        case .work: return "flame.fill"
        case .breakTime: return "leaf.fill"
        case .complete: return "checkmark.seal.fill"
        }
    }

    private var phaseLabel: String {
        switch timer.phase {
        case .idle: return "READY"
        case .work: return "FOCUS"
        case .breakTime: return "BREAK"
        case .complete: return "DONE"
        }
    }

    private var skipTitle: String {
        switch timer.phase {
        case .idle: return "Break"
        case .work: return "Break"
        case .breakTime, .complete: return "Focus"
        }
    }
}

#Preview {
    PomodoroView()
        .frame(width: 470, height: 150)
        .background(Color.black)
}
