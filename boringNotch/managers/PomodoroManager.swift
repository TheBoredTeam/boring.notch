//
//  PomodoroManager.swift
//  boringNotch
//
//  Drives the Pomodoro timer: focus sessions, short breaks and a long break
//  after a configurable number of focus sessions.
//

import AppKit
import Combine
import Defaults
import Foundation

enum PomodoroPhase: Equatable {
    case focus
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    var icon: String {
        switch self {
        case .focus: return "flame.fill"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "moon.zzz.fill"
        }
    }
}

enum PomodoroRunState: Equatable {
    /// Nothing started yet (or the timer was reset).
    case idle
    case running
    /// Stopped part-way through a phase, or waiting for the user to start the next phase.
    case paused
}

@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published private(set) var phase: PomodoroPhase = .focus
    @Published private(set) var runState: PomodoroRunState = .idle
    /// Whole seconds left in the current phase.
    @Published private(set) var remaining: TimeInterval = 25 * 60
    /// Length of the current phase, captured when it starts so changing a setting mid-phase doesn't jump the progress ring.
    @Published private(set) var phaseDuration: TimeInterval = 25 * 60
    /// Focus sessions completed in the current cycle (resets after the long break).
    @Published private(set) var sessionsInCycle: Int = 0

    private var endDate: Date?
    private var tickTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var isRunning: Bool { runState == .running }
    /// True from the first start until the timer is reset; drives the closed-notch countdown.
    var isActive: Bool { runState != .idle }

    var sessionsBeforeLongBreak: Int { max(1, Defaults[.pomodoroSessionsBeforeLongBreak]) }

    var progress: Double {
        guard phaseDuration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / phaseDuration))
    }

    var formattedRemaining: String {
        let total = max(0, Int(remaining))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private init() {
        applyFullDuration()

        // Keep the idle display in sync with the durations chosen in Settings.
        Defaults.publisher(.pomodoroFocusMinutes)
            .sink { [weak self] _ in Task { @MainActor in self?.durationSettingChanged() } }
            .store(in: &cancellables)
        Defaults.publisher(.pomodoroShortBreakMinutes)
            .sink { [weak self] _ in Task { @MainActor in self?.durationSettingChanged() } }
            .store(in: &cancellables)
        Defaults.publisher(.pomodoroLongBreakMinutes)
            .sink { [weak self] _ in Task { @MainActor in self?.durationSettingChanged() } }
            .store(in: &cancellables)

        // Turning the feature off stops the timer and leaves its tab.
        Defaults.publisher(.enablePomodoro)
            .sink { [weak self] change in
                guard !change.newValue else { return }
                Task { @MainActor in
                    guard let self else { return }
                    self.reset()
                    if BoringViewCoordinator.shared.currentView == .pomodoro {
                        BoringViewCoordinator.shared.currentView = .home
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Controls

    func start() {
        guard runState != .running else { return }
        if runState == .idle {
            applyFullDuration()
        }
        endDate = Date().addingTimeInterval(remaining)
        runState = .running
        startTicking()
    }

    func pause() {
        guard runState == .running else { return }
        if let endDate {
            remaining = max(0, ceil(endDate.timeIntervalSinceNow))
        }
        stopTicking()
        runState = .paused
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// Stops everything and goes back to the start of the first focus session.
    func reset() {
        stopTicking()
        phase = .focus
        sessionsInCycle = 0
        runState = .idle
        applyFullDuration()
    }

    /// Jumps to the next phase. If the timer was running it keeps running.
    func skip() {
        advance(naturalCompletion: false)
    }

    // MARK: - Phase handling

    private func tick() {
        guard runState == .running, let endDate else { return }
        let left = endDate.timeIntervalSinceNow
        if left <= 0 {
            remaining = 0
            advance(naturalCompletion: true)
            return
        }
        let whole = ceil(left)
        if whole != remaining {
            remaining = whole
        }
    }

    private func advance(naturalCompletion: Bool) {
        let finished = phase
        let wasRunning = runState == .running
        stopTicking()

        if naturalCompletion {
            playCompletionSound(after: finished)
        }

        switch finished {
        case .focus:
            // A skipped focus session doesn't count towards the long break.
            if naturalCompletion {
                sessionsInCycle += 1
            }
            phase = sessionsInCycle >= sessionsBeforeLongBreak ? .longBreak : .shortBreak
        case .shortBreak:
            phase = .focus
        case .longBreak:
            sessionsInCycle = 0
            phase = .focus
        }

        // After a natural finish the next phase waits (paused, full length) unless auto-start is on,
        // so the closed notch keeps showing what's coming up instead of vanishing.
        runState = .paused
        applyFullDuration()

        let shouldRun = naturalCompletion ? Defaults[.pomodoroAutoStartNext] : wasRunning
        if shouldRun {
            start()
        }
    }

    private func duration(for phase: PomodoroPhase) -> TimeInterval {
        let minutes: Int
        switch phase {
        case .focus: minutes = Defaults[.pomodoroFocusMinutes]
        case .shortBreak: minutes = Defaults[.pomodoroShortBreakMinutes]
        case .longBreak: minutes = Defaults[.pomodoroLongBreakMinutes]
        }
        return TimeInterval(max(1, minutes) * 60)
    }

    private func applyFullDuration() {
        phaseDuration = duration(for: phase)
        remaining = phaseDuration
    }

    private func durationSettingChanged() {
        // Only touch a phase that hasn't been started yet.
        let untouched = runState != .running && remaining == phaseDuration
        if untouched {
            applyFullDuration()
        }
    }

    private func playCompletionSound(after finished: PomodoroPhase) {
        guard Defaults[.pomodoroPlaySound] else { return }
        let name = finished == .focus ? "Hero" : "Glass"
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: - Ticking

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
        endDate = nil
    }
}
