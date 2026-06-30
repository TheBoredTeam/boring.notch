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

    var body: some View {
        HStack(spacing: 12) {
            timerDial
                .frame(width: 94, height: 94)

            VStack(alignment: .leading, spacing: 8) {
                statusLine
                controls
                durationControls
            }
            .frame(width: 260, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .padding(.horizontal, 10)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }

    private var statusLine: some View {
        HStack(spacing: 7) {
            Image(systemName: phaseIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(timer.accent)

            Text(compactPhaseTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if timer.completedFocusSessions > 0 {
                Label("\(timer.completedFocusSessions)", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timerDial: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)

            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 7)

            Circle()
                .trim(from: 0, to: max(timer.progress, timer.phase == .complete ? 1 : 0.018))
                .stroke(timer.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.35), value: timer.progress)

            Text(timer.timeDisplay)
                .font(.system(size: 25, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private var durationControls: some View {
        HStack(spacing: 6) {
            minuteStepper(title: "Focus", value: timer.workMinutes, range: 1...180) { timer.setWorkMinutes($0) }
            minuteStepper(title: "Break", value: timer.breakMinutes, range: 1...60) { timer.setBreakMinutes($0) }
        }
    }

    private func minuteStepper(title: String, value: Int, range: ClosedRange<Int>, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(value)m")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()

            Spacer(minLength: 0)

            Stepper("", value: Binding(
                get: { value },
                set: { onChange(min(max($0, range.lowerBound), range.upperBound)) }
            ), in: range)
            .labelsHidden()
            .controlSize(.mini)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: timer.togglePrimaryAction) {
                Label(timer.primaryButtonTitle, systemImage: timer.primaryButtonIcon)
                    .frame(width: 112)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(timer.accent)

            Button(action: timer.skipPhase) {
                Label(skipTitle, systemImage: "forward.end.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 28)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(skipTitle)

            Button(action: timer.resetToIdle) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
                    .frame(width: 28)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Reset")
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

    private var compactPhaseTitle: String {
        switch timer.phase {
        case .idle: return "Pomodoro"
        case .work: return timer.isRunning ? "Focus" : "Paused"
        case .breakTime: return timer.isRunning ? "Break" : "Paused"
        case .complete: return "Done"
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
}
