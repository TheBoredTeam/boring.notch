//
//  PomodoroManager.swift
//  boringNotch
//
//  Focus timer that cycles between focus sessions and breaks.
//

import AppKit
import Combine
import Defaults
import SwiftUI

enum PomodoroPhase: String {
    case focus
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .focus: return String(localized: "Focus")
        case .shortBreak: return String(localized: "Short break")
        case .longBreak: return String(localized: "Long break")
        }
    }

    var icon: String {
        switch self {
        case .focus: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "figure.walk"
        }
    }

    var tint: Color {
        switch self {
        case .focus: return .orange
        case .shortBreak: return .green
        case .longBreak: return .teal
        }
    }
}

@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published private(set) var phase: PomodoroPhase = .focus
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval
    /// Focus sessions completed in the current cycle (resets after a long break).
    @Published private(set) var completedFocusSessions = 0

    private var endDate: Date?
    private var ticker: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        remaining = Self.duration(for: .focus)

        // Keep an idle timer in sync with duration changes made in Settings.
        Defaults.publisher(keys: .pomodoroFocusMinutes, .pomodoroShortBreakMinutes, .pomodoroLongBreakMinutes, options: [])
            .sink { [weak self] in
                Task { @MainActor in
                    guard let self, !self.isActive else { return }
                    self.remaining = Self.duration(for: self.phase)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - State

    var totalDuration: TimeInterval { Self.duration(for: phase) }

    /// True once the timer has been started and not reset, including while paused.
    var isActive: Bool { isRunning || remaining < totalDuration }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1 - remaining / totalDuration
    }

    var formattedRemaining: String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func duration(for phase: PomodoroPhase) -> TimeInterval {
        let minutes: Int
        switch phase {
        case .focus: minutes = Defaults[.pomodoroFocusMinutes]
        case .shortBreak: minutes = Defaults[.pomodoroShortBreakMinutes]
        case .longBreak: minutes = Defaults[.pomodoroLongBreakMinutes]
        }
        return TimeInterval(max(1, minutes) * 60)
    }

    // MARK: - Controls

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        startTicker()
    }

    func pause() {
        guard isRunning else { return }
        updateRemaining()
        isRunning = false
        endDate = nil
        ticker?.cancel()
    }

    /// Stops the timer and returns to a fresh focus session.
    func reset() {
        stopTicker()
        phase = .focus
        completedFocusSessions = 0
        remaining = Self.duration(for: .focus)
    }

    /// Jumps to the next phase without counting the current one as completed.
    func skip() {
        let wasRunning = isRunning
        stopTicker()
        moveToPhase(nextPhase(countingCompletion: false))
        if wasRunning { start() }
    }

    // MARK: - Timing

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.updateRemaining()
                if self.remaining <= 0 {
                    self.finishPhase()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
        isRunning = false
        endDate = nil
    }

    private func updateRemaining() {
        guard let endDate else { return }
        let newValue = max(0, endDate.timeIntervalSinceNow)
        // Only publish when the displayed second changes to avoid needless redraws.
        if Int(newValue.rounded(.up)) != Int(remaining.rounded(.up)) || newValue == 0 {
            remaining = newValue
        }
    }

    private func finishPhase() {
        let finished = phase
        stopTicker()
        moveToPhase(nextPhase(countingCompletion: true))
        announce(finished: finished)
        if Defaults[.pomodoroAutoStartNext] {
            start()
        }
    }

    private func nextPhase(countingCompletion: Bool) -> PomodoroPhase {
        switch phase {
        case .focus:
            if countingCompletion { completedFocusSessions += 1 }
            let interval = max(1, Defaults[.pomodoroSessionsBeforeLongBreak])
            return completedFocusSessions >= interval ? .longBreak : .shortBreak
        case .longBreak:
            completedFocusSessions = 0
            return .focus
        case .shortBreak:
            return .focus
        }
    }

    private func moveToPhase(_ newPhase: PomodoroPhase) {
        withAnimation(.smooth) {
            phase = newPhase
            remaining = Self.duration(for: newPhase)
        }
    }

    private func announce(finished: PomodoroPhase) {
        if Defaults[.pomodoroPlaySound] {
            NSSound(named: finished == .focus ? "Glass" : "Hero")?.play()
        }
        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if Defaults[.pomodoroShowInClosedNotch] {
            BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .pomodoro)
        }
    }
}
