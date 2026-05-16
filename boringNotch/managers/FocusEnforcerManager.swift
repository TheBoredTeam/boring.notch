//
//  FocusEnforcerManager.swift
//  boringNotch
//

import Combine
import Defaults
import SwiftUI

struct FocusSession: Equatable {
    let taskName: String
    let totalDuration: TimeInterval
    let startTime: Date
    var addedTime: TimeInterval = 0

    var totalWithExtensions: TimeInterval {
        totalDuration + addedTime
    }

    var elapsed: TimeInterval {
        max(0, Date().timeIntervalSince(startTime))
    }

    var remaining: TimeInterval {
        max(0, totalWithExtensions - elapsed)
    }

    var progress: Double {
        guard totalWithExtensions > 0 else { return 1 }
        return min(1, elapsed / totalWithExtensions)
    }

    var isOver: Bool {
        remaining <= 0
    }
}

@MainActor
final class FocusEnforcerManager: ObservableObject {
    static let shared = FocusEnforcerManager()

    @Published private(set) var session: FocusSession?
    @Published private(set) var isFinished: Bool = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var progress: Double = 0

    private var timerTask: Task<Void, Never>?

    private init() {}

    func start(task: String, duration: TimeInterval) {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty
            ? NSLocalizedString("focus_default_task", value: "Focus", comment: "Default task label when none entered")
            : trimmed

        let newSession = FocusSession(
            taskName: label,
            totalDuration: duration,
            startTime: Date()
        )
        session = newSession
        isFinished = false
        remaining = newSession.remaining
        progress = newSession.progress
        startTicking()
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        session = nil
        isFinished = false
        remaining = 0
        progress = 0
    }

    func extend(by seconds: TimeInterval) {
        guard var current = session else { return }
        current.addedTime += seconds
        session = current
        isFinished = false
        refresh()
        if timerTask == nil {
            startTicking()
        }
    }

    private func startTicking() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.refresh()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refresh() {
        guard let session = session else {
            remaining = 0
            progress = 0
            return
        }
        remaining = session.remaining
        progress = session.progress
        if session.isOver && !isFinished {
            isFinished = true
        }
    }
}
