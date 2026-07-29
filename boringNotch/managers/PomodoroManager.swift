//
//  PomodoroManager.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import Foundation
import UserNotifications

public enum PomodoroPhase: String, CaseIterable, Identifiable, Codable {
    case work = "Work"
    case shortBreak = "Short Break"
    case longBreak = "Long Break"

    public var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "bed.double.fill"
        }
    }
}

public enum PomodoroState: String, Codable {
    case idle
    case running
    case paused
}

@MainActor
public class PomodoroManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = PomodoroManager()

    @Published public var phase: PomodoroPhase = .work {
        didSet {
            if state == .idle {
                resetTimeToPhase()
            }
        }
    }

    @Published public var state: PomodoroState = .idle
    @Published public var timeRemaining: TimeInterval = 25 * 60
    @Published public var completedSessionsCount: Int = 0

    private var timerCancellable: AnyCancellable?

    private override init() {
        super.init()
        self.timeRemaining = targetDuration(for: .work)
        setupNotificationPermissions()
        UNUserNotificationCenter.current().delegate = self
    }

    public var targetDuration: TimeInterval {
        targetDuration(for: phase)
    }

    public func targetDuration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .work:
            return Defaults[.pomodoroWorkDuration]
        case .shortBreak:
            return Defaults[.pomodoroShortBreakDuration]
        case .longBreak:
            return Defaults[.pomodoroLongBreakDuration]
        }
    }

    public var progressRatio: Double {
        let total = targetDuration
        guard total > 0 else { return 0 }
        let elapsed = total - timeRemaining
        return max(0, min(1, elapsed / total))
    }

    public func start() {
        guard state != .running else { return }
        if state == .idle {
            timeRemaining = targetDuration
        }
        state = .running
        startTimer()
    }

    public func pause() {
        guard state == .running else { return }
        state = .paused
        stopTimer()
    }

    public func resume() {
        guard state == .paused else { return }
        state = .running
        startTimer()
    }

    public func togglePlayPause() {
        switch state {
        case .running:
            pause()
        case .paused:
            resume()
        case .idle:
            start()
        }
    }

    public func reset() {
        stopTimer()
        state = .idle
        resetTimeToPhase()
    }

    public func skip() {
        stopTimer()
        advanceToNextPhase(didCompleteCurrent: false)
    }

    public func selectPhase(_ newPhase: PomodoroPhase) {
        stopTimer()
        phase = newPhase
        state = .idle
        resetTimeToPhase()
    }

    public func resetTimeToPhase() {
        timeRemaining = targetDuration(for: phase)
    }

    private func startTimer() {
        stopTimer()
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func tick() {
        guard state == .running else { return }

        if timeRemaining > 1 {
            timeRemaining -= 1
        } else {
            timeRemaining = 0
            handlePhaseCompletion()
        }
    }

    public func addMinutes(_ mins: Int) {
        let addedSeconds = TimeInterval(mins * 60)
        timeRemaining = max(10, timeRemaining + addedSeconds)
    }

    public func phaseDisplayName(for phase: PomodoroPhase) -> String {
        switch phase {
        case .work:
            let name = Defaults[.pomodoroWorkName]
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Work" : name
        case .shortBreak:
            let name = Defaults[.pomodoroShortBreakName]
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Short Break" : name
        case .longBreak:
            let name = Defaults[.pomodoroLongBreakName]
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Long Break" : name
        }
    }

    public func applyPreset(workMinutes: Int, shortBreakMinutes: Int, longBreakMinutes: Int) {
        Defaults[.pomodoroWorkDuration] = TimeInterval(workMinutes * 60)
        Defaults[.pomodoroShortBreakDuration] = TimeInterval(shortBreakMinutes * 60)
        Defaults[.pomodoroLongBreakDuration] = TimeInterval(longBreakMinutes * 60)
        resetTimeToPhase()
    }

    private func handlePhaseCompletion() {
        stopTimer()

        // Sound alert
        if Defaults[.pomodoroSoundEnabled] {
            let soundName = Defaults[.pomodoroSoundName]
            NSSound(named: NSSound.Name(soundName))?.play()
        }

        let completedPhase = phase
        let isWorkPhase = (completedPhase == .work)

        if isWorkPhase {
            completedSessionsCount += 1
            sendNotification(
                title: "Pomodoro Completed! 🍅",
                body: "Great job! Time to take a break."
            )
        } else {
            sendNotification(
                title: "Break Finished! ⚡️",
                body: "Ready to focus on your next work session?"
            )
        }

        advanceToNextPhase(didCompleteCurrent: true)
    }

    private func advanceToNextPhase(didCompleteCurrent: Bool) {
        let longBreakInterval = max(1, Defaults[.pomodoroLongBreakInterval])

        if phase == .work {
            if completedSessionsCount > 0 && (completedSessionsCount % longBreakInterval == 0) {
                phase = .longBreak
            } else {
                phase = .shortBreak
            }

            resetTimeToPhase()

            if didCompleteCurrent && Defaults[.pomodoroAutoStartBreaks] {
                start()
            } else {
                state = .idle
            }
        } else {
            phase = .work
            resetTimeToPhase()

            if didCompleteCurrent && Defaults[.pomodoroAutoStartWork] {
                start()
            } else {
                state = .idle
            }
        }
    }

    private func setupNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Force notifications to show as visual banner alerts even if app is focused
        completionHandler([.banner])
    }
}
