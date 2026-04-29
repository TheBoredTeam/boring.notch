//
//  PomodoroManager.swift
//  boringNotch
//
//  Created by Christian Teo on 2026-04-29.
//

import Combine
import Defaults
import Foundation
import SwiftUI

@MainActor
class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    enum PomodoroPhase: String, CaseIterable {
        case work = "Work"
        case shortBreak = "Short Break"
        case longBreak = "Long Break"
        
        var displayName: String {
            return self.rawValue
        }
    }

    // MARK: - Published Properties
    @Published var isRunning: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentPhase: PomodoroPhase = .work
    @Published var remainingSeconds: Int = Defaults[.pomodoroWorkDuration] * 60
    @Published var sessionsCompleted: Int = 0
    
    // Settings (synced with Defaults)
    @Published var workDuration: Int {
        didSet {
            if currentPhase == .work && !isRunning && !isPaused {
                remainingSeconds = workDuration * 60
            }
        }
    }
    @Published var shortBreakDuration: Int {
        didSet {
            if currentPhase == .shortBreak && !isRunning && !isPaused {
                remainingSeconds = shortBreakDuration * 60
            }
        }
    }
    @Published var longBreakDuration: Int {
        didSet {
            if currentPhase == .longBreak && !isRunning && !isPaused {
                remainingSeconds = longBreakDuration * 60
            }
        }
    }
    @Published var sessionsBeforeLongBreak: Int

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init() {
        self.workDuration = Defaults[.pomodoroWorkDuration]
        self.shortBreakDuration = Defaults[.pomodoroShortBreakDuration]
        self.longBreakDuration = Defaults[.pomodoroLongBreakDuration]
        self.sessionsBeforeLongBreak = Defaults[.pomodoroSessionsBeforeLongBreak]
        self.remainingSeconds = workDuration * 60
        
        setupDefaultsObservers()
    }

    private func setupDefaultsObservers() {
        Defaults.publisher(.pomodoroWorkDuration)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                self?.workDuration = change.newValue
                if self?.currentPhase == .work && !(self?.isRunning ?? false) && !(self?.isPaused ?? false) {
                    self?.remainingSeconds = change.newValue * 60
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.pomodoroShortBreakDuration)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                self?.shortBreakDuration = change.newValue
                if self?.currentPhase == .shortBreak && !(self?.isRunning ?? false) && !(self?.isPaused ?? false) {
                    self?.remainingSeconds = change.newValue * 60
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.pomodoroLongBreakDuration)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                self?.longBreakDuration = change.newValue
                if self?.currentPhase == .longBreak && !(self?.isRunning ?? false) && !(self?.isPaused ?? false) {
                    self?.remainingSeconds = change.newValue * 60
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.pomodoroSessionsBeforeLongBreak)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                self?.sessionsBeforeLongBreak = change.newValue
            }
            .store(in: &cancellables)
    }

    // MARK: - Timer Controls
    func start() {
        guard !isRunning else { return }
        isRunning = true
        isPaused = false
        
        timer?.invalidate()
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

    func reset() {
        isRunning = false
        isPaused = false
        timer?.invalidate()
        timer = nil
        
        switch currentPhase {
        case .work:
            remainingSeconds = workDuration * 60
        case .shortBreak:
            remainingSeconds = shortBreakDuration * 60
        case .longBreak:
            remainingSeconds = longBreakDuration * 60
        }
    }
    
    func resetSessions() {
        sessionsCompleted = 0
    }

    func resetAll() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
        currentPhase = .work
        sessionsCompleted = 0
        remainingSeconds = workDuration * 60
    }

    func skip() {
        // Move to next phase without waiting for timer
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

    // MARK: - Computed Properties
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
    
    var phaseColor: Color {
        switch currentPhase {
        case .work: return .red
        case .shortBreak: return .green
        case .longBreak: return .blue
        }
    }
    
    var sessionDots: String {
        String(repeating: "• ", count: min(sessionsCompleted, 10))
    }
}