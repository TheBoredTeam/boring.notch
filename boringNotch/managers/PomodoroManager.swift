//
//  PomodoroManager.swift
//  boringNotch
//
//  Created by Claw on 2026-04-28.
//

import Combine
import Defaults
import Foundation
import SwiftUI

@MainActor
class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published var isRunning: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentPhase: PomodoroPhase = .work
    @Published var remainingSeconds: Int = 25 * 60
    @Published var sessionsCompleted: Int = 0
    @Published var showPanel: Bool = false

    @Published var workDuration: Int = Defaults[.pomodoroWorkDuration]
    @Published var shortBreakDuration: Int = Defaults[.pomodoroShortBreakDuration]
    @Published var longBreakDuration: Int = Defaults[.pomodoroLongBreakDuration]
    @Published var sessionsBeforeLongBreak: Int = Defaults[.pomodoroSessionsBeforeLongBreak]

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    enum PomodoroPhase: String {
        case work = "Focus"
        case shortBreak = "Short Break"
        case longBreak = "Long Break"
    }

    init() {
        Defaults.publisher(.pomodoroWorkDuration)
            .sink { [weak self] change in
                self?.workDuration = change.newValue
                if self?.currentPhase == .work && !(self?.isRunning ?? false) {
                    self?.remainingSeconds = change.newValue * 60
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.pomodoroShortBreakDuration)
            .sink { [weak self] change in
                self?.shortBreakDuration = change.newValue
                if self?.currentPhase == .shortBreak && !(self?.isRunning ?? false) {
                    self?.remainingSeconds = change.newValue * 60
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.pomodoroLongBreakDuration)
            .sink { [weak self] change in
                self?.longBreakDuration = change.newValue
                if self?.currentPhase == .longBreak && !(self?.isRunning ?? false) {
                    self?.remainingSeconds = change.newValue * 60
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.pomodoroSessionsBeforeLongBreak)
            .sink { [weak self] change in
                self?.sessionsBeforeLongBreak = change.newValue
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        isPaused = false
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func pause() {
        isPaused = true
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        start()
    }

    func stop() {
        isRunning = false
        isPaused = false
        timer?.invalidate()
        timer = nil
        reset()
    }

    func reset() {
        switch currentPhase {
        case .work:
            remainingSeconds = workDuration * 60
        case .shortBreak:
            remainingSeconds = shortBreakDuration * 60
        case .longBreak:
            remainingSeconds = longBreakDuration * 60
        }
    }

    func skip() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
        transitionToNextPhase()
    }

    private func tick() {
        guard remainingSeconds > 0 else {
            timer?.invalidate()
            timer = nil
            isRunning = false
            transitionToNextPhase()
            return
        }
        remainingSeconds -= 1
    }

    private func transitionToNextPhase() {
        switch currentPhase {
        case .work:
            sessionsCompleted += 1
            if sessionsCompleted % sessionsBeforeLongBreak == 0 {
                currentPhase = .longBreak
                remainingSeconds = longBreakDuration * 60
            } else {
                currentPhase = .shortBreak
                remainingSeconds = shortBreakDuration * 60
            }
        case .shortBreak, .longBreak:
            currentPhase = .work
            remainingSeconds = workDuration * 60
        }
    }

    func togglePanel() {
        showPanel.toggle()
    }

    var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var progress: Double {
        let total: Int
        switch currentPhase {
        case .work: total = workDuration * 60
        case .shortBreak: total = shortBreakDuration * 60
        case .longBreak: total = longBreakDuration * 60
        }
        guard total > 0 else { return 0 }
        return Double(total - remainingSeconds) / Double(total)
    }
}
