//
//  TimerManager.swift
//  boringNotch
//
//  Created by Claude on 2026-07-05.
//

import AppKit
import Combine
import Defaults
import SwiftUI
import UserNotifications

enum TimerMode: String {
    case work = "Focus"
    case shortBreak = "Short break"
    case longBreak = "Long break"
    case custom = "Timer"

    var isPomodoro: Bool { self != .custom }
}

@MainActor
final class TimerManager: ObservableObject {
    static let shared = TimerManager()

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var mode: TimerMode = .custom
    @Published private(set) var completedSessions: Int = 0

    private var endDate: Date?
    private var tickTimer: Timer?
    private var enabledCancellable: AnyCancellable?

    private init() {
        enabledCancellable = Defaults.publisher(.enableTimerFeature)
            .sink { change in
                Task { @MainActor in
                    guard !change.newValue else { return }
                    TimerManager.shared.stop()
                    if BoringViewCoordinator.shared.currentView == .timer {
                        BoringViewCoordinator.shared.showEmpty()
                    }
                }
            }
    }

    var isTimerActive: Bool { isRunning || isPaused }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }

    var formattedRemainingTime: String {
        let seconds = max(0, remainingSeconds)
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Controls

    func start(durationMinutes: Int, mode: TimerMode = .custom) {
        guard durationMinutes > 0 else { return }
        if mode == .work && !isTimerActive {
            completedSessions = 0
        }
        self.mode = mode
        totalSeconds = durationMinutes * 60
        remainingSeconds = totalSeconds
        endDate = Date().addingTimeInterval(TimeInterval(totalSeconds))
        isRunning = true
        isPaused = false
        startTicking()
        requestNotificationAuthorizationIfNeeded()
    }

    func startPomodoro() {
        completedSessions = 0
        start(durationMinutes: Defaults[.pomodoroWorkMinutes], mode: .work)
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        isPaused = true
        stopTicking()
        endDate = nil
    }

    func resume() {
        guard isPaused else { return }
        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        isRunning = true
        isPaused = false
        startTicking()
    }

    func stop() {
        isRunning = false
        isPaused = false
        remainingSeconds = 0
        totalSeconds = 0
        mode = .custom
        endDate = nil
        stopTicking()
    }

    func skipPhase() {
        guard mode.isPomodoro else {
            stop()
            return
        }
        advancePhase()
    }

    // MARK: - Ticking

    private func startTicking() {
        stopTicking()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        tick()
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        let remaining = Int(endDate.timeIntervalSinceNow.rounded())
        remainingSeconds = max(0, remaining)
        if remaining <= 0 {
            timerCompleted()
        }
    }

    // MARK: - Completion

    private func timerCompleted() {
        stopTicking()
        isRunning = false
        endDate = nil

        if Defaults[.timerSoundEnabled] {
            NSSound(named: "Glass")?.play()
        }
        if Defaults[.timerNotificationEnabled] {
            postCompletionNotification()
        }
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .timer)

        if mode.isPomodoro {
            if mode == .work {
                completedSessions += 1
            }
            if Defaults[.pomodoroAutoAdvance] {
                advancePhase()
            } else {
                isPaused = false
                remainingSeconds = 0
            }
        } else {
            stop()
        }
    }

    private func advancePhase() {
        switch mode {
        case .work:
            let useLongBreak =
                completedSessions > 0
                && completedSessions % Defaults[.pomodoroSessionsBeforeLongBreak] == 0
            let nextMode: TimerMode = useLongBreak ? .longBreak : .shortBreak
            let minutes = useLongBreak
                ? Defaults[.pomodoroLongBreakMinutes]
                : Defaults[.pomodoroShortBreakMinutes]
            start(durationMinutes: minutes, mode: nextMode)
        case .shortBreak, .longBreak:
            start(durationMinutes: Defaults[.pomodoroWorkMinutes], mode: .work)
        case .custom:
            stop()
        }
    }

    // MARK: - Notifications

    private var didRequestNotificationAuthorization = false

    private func requestNotificationAuthorizationIfNeeded() {
        guard Defaults[.timerNotificationEnabled], !didRequestNotificationAuthorization else { return }
        didRequestNotificationAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postCompletionNotification() {
        let content = UNMutableNotificationContent()
        switch mode {
        case .work:
            content.title = String(localized: "Focus session complete")
            content.body = String(localized: "Time for a break!")
        case .shortBreak, .longBreak:
            content.title = String(localized: "Break is over")
            content.body = String(localized: "Time to get back to work.")
        case .custom:
            content.title = String(localized: "Timer finished")
            content.body = String(localized: "Your timer is done.")
        }
        let request = UNNotificationRequest(
            identifier: "boringNotch.timer.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
