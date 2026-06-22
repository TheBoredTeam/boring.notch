//
//  PomodoroManager.swift
//  boringNotch
//

import Combine
import Defaults
import Foundation
import AppKit
import UserNotifications

enum PomodoroPhase {
    case work
    case shortBreak
    case longBreak

    var label: String {
        switch self {
        case .work: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
}

// Per-day focus record, persisted via Defaults.
struct PomodoroDayStat: Codable, Defaults.Serializable {
    var pomodoros: Int
    var focusSeconds: Double
}

@MainActor
class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published var phase: PomodoroPhase = .work
    @Published var timeRemaining: Double = Defaults[.pomodoroWorkDuration] * 60
    @Published var isRunning: Bool = false
    @Published var completedPomodoros: Int = 0

    // Today's running totals, mirrored for reactive UI.
    @Published var todayPomodoros: Int = 0
    @Published var todayFocusSeconds: Double = 0

    private var timer: Timer?
    private var endDate: Date?
    private var cancellables = Set<AnyCancellable>()
    // Held so the chime isn't deallocated mid-playback (NSSound doesn't retain
    // itself during async play()).
    private var completionSound: NSSound?

    private init() {
        loadTodayStats()

        // Keep the displayed time in sync when durations change while idle.
        let workChanges = Defaults.publisher(.pomodoroWorkDuration).map { _ in () }
        let shortChanges = Defaults.publisher(.pomodoroShortBreakDuration).map { _ in () }
        let longChanges = Defaults.publisher(.pomodoroLongBreakDuration).map { _ in () }
        workChanges
            .merge(with: shortChanges, longChanges)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.isRunning else { return }
                    self.timeRemaining = self.totalDuration
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Durations (sourced from Settings)

    private var workDuration: Double { Defaults[.pomodoroWorkDuration] * 60 }
    private var shortBreakDuration: Double { Defaults[.pomodoroShortBreakDuration] * 60 }
    private var longBreakDuration: Double { Defaults[.pomodoroLongBreakDuration] * 60 }
    private var cyclesBeforeLongBreak: Int { max(1, Defaults[.pomodoroCyclesBeforeLongBreak]) }

    var totalDuration: Double {
        switch phase {
        case .work: return workDuration
        case .shortBreak: return shortBreakDuration
        case .longBreak: return longBreakDuration
        }
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1.0 - (timeRemaining / totalDuration)
    }

    // MARK: - Controls

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if phase == .work { setDND(true) }
        // Anchor to wall-clock time so the countdown stays accurate regardless
        // of how often (or how many times) the timer fires.
        endDate = Date().addingTimeInterval(timeRemaining)
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        endDate = nil
    }

    func pause() {
        isRunning = false
        stopTimer()
        setDND(false)
    }

    func reset() {
        pause()
        timeRemaining = totalDuration
    }

    func skip() {
        pause()
        // Manual skip doesn't credit focus time toward stats.
        advance(credit: false)
    }

    private func tick() {
        guard let endDate else { return }
        let remaining = endDate.timeIntervalSinceNow
        if remaining <= 0 {
            timeRemaining = 0
            // Capture the phase that just elapsed BEFORE advancing, so the
            // chime and notification describe what actually finished.
            let finishedPhase = phase
            advance(credit: true)
            playCompletionChime()
            notify(finishedPhase: finishedPhase)
        } else {
            timeRemaining = remaining
        }
    }

    private func advance(credit: Bool = true) {
        switch phase {
        case .work:
            if credit {
                completedPomodoros += 1
                recordCompletedPomodoro(focusSeconds: workDuration)
            }
            if completedPomodoros % cyclesBeforeLongBreak == 0 && completedPomodoros > 0 {
                phase = .longBreak
                timeRemaining = longBreakDuration
            } else {
                phase = .shortBreak
                timeRemaining = shortBreakDuration
            }
        case .shortBreak, .longBreak:
            phase = .work
            timeRemaining = workDuration
        }
        isRunning = false
        stopTimer()
        setDND(false)
    }

    // MARK: - Statistics

    private static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func loadTodayStats() {
        let today = Defaults[.pomodoroStats][Self.dayKey()] ?? PomodoroDayStat(pomodoros: 0, focusSeconds: 0)
        todayPomodoros = today.pomodoros
        todayFocusSeconds = today.focusSeconds
    }

    private func recordCompletedPomodoro(focusSeconds: Double) {
        let key = Self.dayKey()
        var stats = Defaults[.pomodoroStats]
        var day = stats[key] ?? PomodoroDayStat(pomodoros: 0, focusSeconds: 0)
        day.pomodoros += 1
        day.focusSeconds += focusSeconds
        stats[key] = day
        Defaults[.pomodoroStats] = stats
        todayPomodoros = day.pomodoros
        todayFocusSeconds = day.focusSeconds
    }

    /// Total focus seconds over the trailing 7 days (inclusive of today).
    func weekFocusSeconds() -> Double {
        let stats = Defaults[.pomodoroStats]
        let cal = Calendar(identifier: .gregorian)
        return (0..<7).reduce(0.0) { sum, offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return sum }
            return sum + (stats[Self.dayKey(date)]?.focusSeconds ?? 0)
        }
    }

    func weekPomodoros() -> Int {
        let stats = Defaults[.pomodoroStats]
        let cal = Calendar(identifier: .gregorian)
        return (0..<7).reduce(0) { sum, offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return sum }
            return sum + (stats[Self.dayKey(date)]?.pomodoros ?? 0)
        }
    }

    func resetStats() {
        Defaults[.pomodoroStats] = [:]
        completedPomodoros = 0
        todayPomodoros = 0
        todayFocusSeconds = 0
    }

    // MARK: - Do Not Disturb (via macOS Shortcuts)

    private func setDND(_ on: Bool) {
        guard Defaults[.pomodoroAutoDND] else { return }
        let shortcutName = on ? "BoringNotch Focus On" : "BoringNotch Focus Off"
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", shortcutName]
            try? process.run()
        }
    }

    // MARK: - Completion sound

    /// Plays a clear system chime the moment a phase ends. Independent of the
    /// notification banner, so you hear it even if notifications are denied.
    private func playCompletionChime() {
        guard Defaults[.pomodoroCompletionSound] else { return }
        // Retain the sound — a fire-and-forget `NSSound(named:)?.play()` can be
        // deallocated before it's audible. Fall back through a few stock sounds.
        let sound = NSSound(named: "Glass")
            ?? NSSound(named: "Hero")
            ?? NSSound(named: "Funk")
            ?? NSSound(named: "Ping")
        sound?.volume = 1.0
        completionSound = sound
        sound?.play()
    }

    // MARK: - Notifications

    private func notify(finishedPhase: PomodoroPhase) {
        let finishedWork = finishedPhase == .work
        Task.detached {
            let center = UNUserNotificationCenter.current()
            let granted = await withCheckedContinuation { cont in
                center.requestAuthorization(options: [.alert, .sound]) { ok, _ in cont.resume(returning: ok) }
            }
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = finishedWork ? "Break time!" : "Back to work!"
            content.body = finishedWork
                ? "Great focus session. Take a break."
                : "Break's over. Time to focus."
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
