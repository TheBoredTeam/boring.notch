//
//  TimerManager.swift
//  boringNotch
//

import Foundation

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
    @Published var totalDuration: TimeInterval = 0
    @Published var remainingTime: TimeInterval = 0

    private var timer: Timer?
    private var lastTickDate: Date?

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1.0 - (remainingTime / totalDuration)
    }

    // Adds time cumulatively; when running/paused also extends total so the ring stays meaningful
    func addPreset(_ seconds: TimeInterval) {
        remainingTime += seconds
        totalDuration += seconds
    }

    func start() {
        guard remainingTime > 0 else { return }
        state = .running
        lastTickDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
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
        totalDuration = 0
        remainingTime = 0
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
