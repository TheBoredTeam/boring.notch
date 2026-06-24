//
//  PomodoroManager.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import SwiftUI
import UserNotifications

class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published var phase: PomodoroPhase = .focus
    @Published var remainingSeconds: Int = 1500
    @Published var isRunning: Bool = false
    @Published var completedSessions: Int = 0

    private var timerCancellable: AnyCancellable?
    private var notificationRequested = false

    var totalSeconds: Int {
        switch phase {
        case .focus: return Defaults[.pomodoroFocusDuration]
        case .shortBreak: return Defaults[.pomodoroShortBreakDuration]
        case .longBreak: return Defaults[.pomodoroLongBreakDuration]
        }
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }

    var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var nextPhase: PomodoroPhase {
        switch phase {
        case .focus:
            if completedSessions + 1 >= Defaults[.pomodoroSessionsBeforeLongBreak] {
                return .longBreak
            } else {
                return .shortBreak
            }
        case .shortBreak, .longBreak:
            return .focus
        }
    }

    var phaseLabel: String {
        switch phase {
        case .focus: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    var phaseIcon: String {
        switch phase {
        case .focus: return "target"
        case .shortBreak: return "cup.and.saucer"
        case .longBreak: return "cup.and.saucer.fill"
        }
    }

    private init() {
        remainingSeconds = Defaults[.pomodoroFocusDuration]
    }

    func start() {
        requestNotificationPermissionIfNeeded()
        startTimer()
    }

    func pause() {
        timerCancellable?.cancel()
        timerCancellable = nil
        isRunning = false
    }

    func resume() {
        start()
    }

    func skip() {
        pause()
        advancePhase()
    }

    func reset() {
        pause()
        phase = .focus
        remainingSeconds = Defaults[.pomodoroFocusDuration]
        completedSessions = 0
    }

    private func startTimer() {
        timerCancellable?.cancel()
        isRunning = true
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard isRunning else { return }
        if remainingSeconds > 0 {
            remainingSeconds -= 1
        }
        if remainingSeconds <= 0 {
            phaseComplete()
        }
    }

    private func phaseComplete() {
        timerCancellable?.cancel()
        timerCancellable = nil
        isRunning = false

        playSound()
        sendNotification()

        if autoStartNext() {
            advancePhase()
            startTimer()
        } else {
            advancePhase()
        }
    }

    private func advancePhase() {
        switch phase {
        case .focus:
            completedSessions += 1
            if completedSessions >= Defaults[.pomodoroSessionsBeforeLongBreak] {
                phase = .longBreak
                remainingSeconds = Defaults[.pomodoroLongBreakDuration]
                completedSessions = 0
            } else {
                phase = .shortBreak
                remainingSeconds = Defaults[.pomodoroShortBreakDuration]
            }
        case .shortBreak, .longBreak:
            phase = .focus
            remainingSeconds = Defaults[.pomodoroFocusDuration]
        }

        Task { @MainActor in
            BoringViewCoordinator.shared.toggleSneakPeek(
                status: true,
                type: .pomodoro,
                duration: 3.0,
                value: 0,
                icon: phaseIcon
            )
        }
    }

    private func autoStartNext() -> Bool {
        switch phase {
        case .focus: return Defaults[.pomodoroAutoStartBreaks]
        case .shortBreak, .longBreak: return Defaults[.pomodoroAutoStartFocus]
        }
    }

    private func playSound() {
        let soundSetting = Defaults[.pomodoroNotificationSound]
        guard soundSetting != .silent else { return }

        let soundName: String
        switch soundSetting {
        case .chime: soundName = "Glass"
        case .bell: soundName = "Funk"
        case .silent: return
        }

        if let sound = NSSound(named: soundName) {
            sound.play()
        } else {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

    private func sendNotification() {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "\(phaseLabel) Complete"
        content.body = "Time for \(phaseLabel(for: nextPhase))."
        content.sound = Defaults[.pomodoroNotificationSound] != .silent
            ? .default
            : nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private func phaseLabel(for phase: PomodoroPhase) -> String {
        switch phase {
        case .focus: return "Focus (\(Defaults[.pomodoroFocusDuration] / 60)m)"
        case .shortBreak: return "Short Break (\(Defaults[.pomodoroShortBreakDuration] / 60)m)"
        case .longBreak: return "Long Break (\(Defaults[.pomodoroLongBreakDuration] / 60)m)"
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        guard !notificationRequested else { return }
        notificationRequested = true
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if !granted {
                Logger.log("Notification permission denied for Pomodoro", category: .warning)
            }
        }
    }
}
