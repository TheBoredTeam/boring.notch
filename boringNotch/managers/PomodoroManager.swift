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
    private var cancellables = Set<AnyCancellable>()

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
        isRunning = true
        if phase == .work { setDND(true) }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        setDND(false)
    }

    func reset() {
        pause()
        timeRemaining = totalDuration
    }

    func skip() {
        pause()
        advance()
    }

    private func tick() {
        guard timeRemaining > 0 else {
            advance()
            notify()
            return
        }
        timeRemaining -= 1
    }

    private func advance() {
        switch phase {
        case .work:
            completedPomodoros += 1
            recordCompletedPomodoro(focusSeconds: workDuration)
            if completedPomodoros % cyclesBeforeLongBreak == 0 {
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
        timer?.invalidate()
        timer = nil
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

    // MARK: - Notifications

    private func notify() {
        let isWork = phase == .work
        Task.detached {
            let center = UNUserNotificationCenter.current()
            let granted = await withCheckedContinuation { cont in
                center.requestAuthorization(options: [.alert, .sound]) { ok, _ in cont.resume(returning: ok) }
            }
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = isWork ? "Break time!" : "Back to work!"
            content.body = isWork
                ? "Great focus session. Take a break."
                : "Break's over. Time to focus."
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
