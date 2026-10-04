//
//  FocusTimerManager.swift
//  boringNotch
//
//  Pomodoro-style focus timer that keeps running while the notch is closed.
//

import AppKit
import Combine
import Defaults

@MainActor
final class FocusTimerManager: ObservableObject {
    static let shared = FocusTimerManager()

    enum Phase: String, CaseIterable, Identifiable {
        case focus = "Focus"
        case shortBreak = "Short break"
        case longBreak = "Long break"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .focus: return "brain.head.profile"
            case .shortBreak: return "cup.and.saucer.fill"
            case .longBreak: return "figure.walk"
            }
        }

        var durationKey: Defaults.Key<Int> {
            switch self {
            case .focus: return .focusDurationMinutes
            case .shortBreak: return .shortBreakDurationMinutes
            case .longBreak: return .longBreakDurationMinutes
            }
        }
    }

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var duration: TimeInterval
    @Published private(set) var isRunning = false
    @Published private(set) var completedFocusSessions = 0

    private var endDate: Date?
    private var tickTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    /// True once the timer has been started and not reset, so the closed-notch countdown can show.
    var isActive: Bool { isRunning || remaining < duration }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return 1 - remaining / duration
    }

    var formattedRemaining: String {
        let total = Int(remaining.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private init() {
        let initial = TimeInterval(max(1, Defaults[.focusDurationMinutes]) * 60)
        duration = initial
        remaining = initial

        // Pick up new durations from settings while the timer is idle.
        for key in [Defaults.Key<Int>.focusDurationMinutes, .shortBreakDurationMinutes, .longBreakDurationMinutes] {
            Defaults.publisher(key, options: [])
                .sink { [weak self] _ in
                    Task { @MainActor in
                        guard let self, !self.isActive else { return }
                        self.select(self.phase)
                    }
                }
                .store(in: &cancellables)
        }
    }

    // MARK: Controls

    func start() {
        guard !isRunning, remaining > 0 else { return }
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func pause() {
        guard isRunning else { return }
        tick()
        stopTicking()
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func reset() {
        stopTicking()
        remaining = duration
    }

    /// Jumps to the next phase without counting the current one as finished.
    func skip() {
        advance(countSession: false)
    }

    func select(_ newPhase: Phase) {
        stopTicking()
        phase = newPhase
        duration = TimeInterval(max(1, Defaults[newPhase.durationKey]) * 60)
        remaining = duration
    }

    func addMinute() {
        remaining += 60
        duration = max(duration, remaining)
        if isRunning {
            endDate = endDate?.addingTimeInterval(60)
        }
    }

    // MARK: Internals

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            finish()
        }
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
        endDate = nil
        isRunning = false
    }

    private func finish() {
        if Defaults[.playTimerFinishedSound] {
            NSSound(named: phase == .focus ? "Glass" : "Hero")?.play()
        }
        advance(countSession: true)
    }

    private func advance(countSession: Bool) {
        let next: Phase
        switch phase {
        case .focus:
            if countSession {
                completedFocusSessions += 1
            }
            let interval = max(1, Defaults[.sessionsBeforeLongBreak])
            next = (countSession && completedFocusSessions % interval == 0) ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            next = .focus
        }
        select(next)
    }
}
