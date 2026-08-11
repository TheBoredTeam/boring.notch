//
//  PomodoroManager.swift
//  boringNotch
//

import Combine
import Defaults
import Foundation
import AppKit
import UserNotifications
import IOKit.pwr_mgt

#if DEBUG
// TEMP diagnostic: append the completion path to a file for verification.
func pomoDebug(_ s: String) {
    let line = "\(Date().timeIntervalSince1970) \(s)\n"
    let url = URL(fileURLWithPath: "/tmp/pomodoro_debug.log")
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        if let d = line.data(using: .utf8) { h.write(d) }
        try? h.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}
#else
func pomoDebug(_ s: String) {}
#endif

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
    // Held so chimes aren't deallocated mid-playback (NSSound doesn't retain
    // itself during async play()). An array supports repeated chimes.
    private var completionSounds: [NSSound] = []

    // IOKit power assertion held while a session runs, so the Mac doesn't idle-
    // sleep mid-session and the chime actually fires when time's up.
    private var sleepAssertionID: IOPMAssertionID = 0
    private var sleepAsserted = false

    private init() {
        loadTodayStats()

        // Request permission upfront — at completion time the system may silently
        // deny a first-time request, leaving users with no banner after 25 minutes.
        Task {
            try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }

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
        setSleepPrevention(true)
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
        setSleepPrevention(false)
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
            pomoDebug("tick reached zero, phase=\(phase)")
            // Capture the phase that just elapsed BEFORE advancing, so the
            // chime and notification describe what actually finished.
            let finishedPhase = phase
            advance(credit: true)
            playCompletionChime()
            notify(finishedPhase: finishedPhase)
            // Optionally roll straight into the next session right after the chime.
            if Defaults[.pomodoroAutoStartNext] {
                start()
            }
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
        setSleepPrevention(false)
    }

    // MARK: - Keep-awake (so the chime fires even if you walk away)

    /// Holds an IOKit assertion that prevents *idle system sleep* during a
    /// session, so the timer keeps running and the chime plays even when the
    /// display has slept. Note: this cannot defeat a physically closed lid
    /// (clamshell sleep) without an external display + power.
    private func setSleepPrevention(_ on: Bool) {
        if on {
            guard Defaults[.pomodoroPreventSleep], !sleepAsserted else { return }
            let ok = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "BoringNotch focus session" as CFString,
                &sleepAssertionID
            )
            sleepAsserted = (ok == kIOReturnSuccess)
        } else if sleepAsserted {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = 0
            sleepAsserted = false
        }
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

    /// Built-in chime choices (names of files in /System/Library/Sounds), plus
    /// the sentinel "Custom" which uses the user-picked audio file.
    static let chimeOptions = ["Glass", "Hero", "Ping", "Submarine", "Funk",
                               "Bottle", "Blow", "Tink", "Sosumi", "Custom"]

    /// Loads the user's selected chime — a stock system sound, or a custom audio
    /// file (their own "ringtone"). Falls back through stock sounds if missing.
    private func loadChimeSound() -> NSSound? {
        let name = Defaults[.pomodoroChimeSound]
        if name == "Custom" {
            let path = Defaults[.pomodoroCustomChimePath]
            if !path.isEmpty, FileManager.default.fileExists(atPath: path),
               let s = NSSound(contentsOfFile: path, byReference: true) {
                return s
            }
        } else if let s = NSSound(named: name) {
            return s
        }
        return NSSound(named: "Glass") ?? NSSound(named: "Hero") ?? NSSound(named: "Ping")
    }

    /// Plays the selected chime the moment a phase ends. Independent of the
    /// notification banner, so you hear it even if notifications are denied.
    private func playCompletionChime() {
        guard Defaults[.pomodoroCompletionSound] else { return }
        playChime(times: max(1, min(3, Defaults[.pomodoroChimeCount])))
    }

    /// Plays the configured chime `times` times in sequence. Public so Settings
    /// can preview it. Each sound is retained until the sequence finishes.
    func playChime(times: Int = 1) {
        completionSounds.removeAll()
        for i in 0..<max(1, times) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.15) { [weak self] in
                guard let self, let s = self.loadChimeSound() else { return }
                s.volume = 1.0
                self.completionSounds.append(s)
                s.play()
            }
        }
    }

    // MARK: - Notifications

    private func notify(finishedPhase: PomodoroPhase) {
        let finishedWork = finishedPhase == .work
        Task.detached {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            pomoDebug("notify: authStatus=\(settings.authorizationStatus.rawValue)")
            let granted = await withCheckedContinuation { cont in
                center.requestAuthorization(options: [.alert, .sound]) { ok, err in
                    pomoDebug("notify: requestAuthorization granted=\(ok) err=\(String(describing: err))")
                    cont.resume(returning: ok)
                }
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
