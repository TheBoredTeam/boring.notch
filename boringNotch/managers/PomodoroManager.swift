//
//  PomodoroManager.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import Foundation

@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    static let presetDurations = [1, 10, 30]
    static let minuteRange = 1...180

    @Published private(set) var durationMinutes: Int
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false

    private var timerTask: Task<Void, Never>?

    var progress: Double {
        let total = durationMinutes * 60
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - Double(remainingSeconds) / Double(total)))
    }

    var formattedRemaining: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var canEditDuration: Bool {
        !isRunning
    }

    private init() {
        let saved = Defaults[.pomodoroDurationMinutes]
        let clamped = Self.clampMinutes(saved)
        durationMinutes = clamped
        remainingSeconds = clamped * 60
    }

    func setDuration(minutes: Int) {
        guard canEditDuration else { return }
        let clamped = Self.clampMinutes(minutes)
        durationMinutes = clamped
        remainingSeconds = clamped * 60
        Defaults[.pomodoroDurationMinutes] = clamped
    }

    func applyPreset(_ minutes: Int) {
        setDuration(minutes: minutes)
    }

    func start() {
        if remainingSeconds <= 0 {
            remainingSeconds = durationMinutes * 60
        }
        isRunning = true
        isPaused = false
        runTimer()
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        isPaused = true
        timerTask?.cancel()
        timerTask = nil
    }

    func togglePlayPause() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }

    func reset() {
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
        isPaused = false
        remainingSeconds = durationMinutes * 60
    }

    private func runTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, self.isRunning else { return }

                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                }

                if self.remainingSeconds <= 0 {
                    self.isRunning = false
                    self.isPaused = false
                    self.playCompletionAlarm()
                    return
                }
            }
        }
    }

    func playCompletionAlarm() {
        guard Defaults[.pomodoroPlayAlarmSound] else { return }
        SystemSoundPlayer.play(soundName: Defaults[.pomodoroAlarmSoundName])
    }

    private static func clampMinutes(_ minutes: Int) -> Int {
        min(max(minutes, minuteRange.lowerBound), minuteRange.upperBound)
    }
}
