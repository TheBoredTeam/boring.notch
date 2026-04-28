//
//  TimerManager.swift
//  boringNotch
//

import Foundation
import Combine

enum TimerState {
    case idle
    case running
    case paused
    case finished
}

@MainActor
class TimerManager: ObservableObject {
    static let shared = TimerManager()

    @Published var state: TimerState = .idle
    @Published var totalDuration: TimeInterval = 600
    @Published var remainingTime: TimeInterval = 600

    private var timer: Timer?
    private var lastTickDate: Date?

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1.0 - (remainingTime / totalDuration)
    }

    // Sets a new duration (only when idle)
    func setDuration(_ seconds: TimeInterval) {
        guard state == .idle else { return }
        totalDuration = max(60, seconds)
        remainingTime = totalDuration
    }

    // Adds or removes time from the current remaining time
    func adjustTime(by delta: TimeInterval) {
        let newTime = remainingTime + delta
        remainingTime = max(60, newTime)
        if state == .idle {
            totalDuration = remainingTime
        }
    }

    func start() {
        guard state == .idle || state == .paused else { return }
        state = .running
        lastTickDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    func pause() {
        guard state == .running else { return }
        timer?.invalidate()
        timer = nil
        state = .paused
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        state = .idle
        remainingTime = totalDuration
    }

    private func tick() {
        let now = Date()
        let delta = lastTickDate.map { now.timeIntervalSince($0) } ?? 0.5
        lastTickDate = now
        remainingTime = max(0, remainingTime - delta)
        if remainingTime <= 0 {
            timer?.invalidate()
            timer = nil
            state = .finished
        }
    }
}
