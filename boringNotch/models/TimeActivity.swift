//
//  TimeActivity.swift
//  boringNotch
//
//  Adapted from Cris2907/not-so-boring-notch.
//

import Foundation

enum TimeActivityKind: String, Codable, CaseIterable, Equatable {
    case timer
    case stopwatch
}

enum TimeActivityPhase: String, Codable, Equatable {
    case running
    case paused
    case finished
}

struct TimeActivitySnapshot: Codable, Equatable {
    static let maximumTimerDuration: TimeInterval = (99 * 60 * 60) + (59 * 60) + 59

    var kind: TimeActivityKind
    var phase: TimeActivityPhase
    var duration: TimeInterval
    var accumulatedElapsed: TimeInterval
    var resumedAt: Date?
    var completionSoundPlayed: Bool

    static func timer(duration: TimeInterval, startedAt: Date) -> TimeActivitySnapshot? {
        guard isValidTimerDuration(duration) else { return nil }
        return TimeActivitySnapshot(
            kind: .timer,
            phase: .running,
            duration: duration,
            accumulatedElapsed: 0,
            resumedAt: startedAt,
            completionSoundPlayed: false
        )
    }

    static func stopwatch(startedAt: Date) -> TimeActivitySnapshot {
        TimeActivitySnapshot(
            kind: .stopwatch,
            phase: .running,
            duration: 0,
            accumulatedElapsed: 0,
            resumedAt: startedAt,
            completionSoundPlayed: false
        )
    }

    static func isValidTimerDuration(_ duration: TimeInterval) -> Bool {
        duration >= 1 && duration <= maximumTimerDuration
    }

    func elapsed(at date: Date) -> TimeInterval {
        let activeElapsed: TimeInterval
        if phase == .running, let resumedAt {
            activeElapsed = max(0, date.timeIntervalSince(resumedAt))
        } else {
            activeElapsed = 0
        }

        let total = max(0, accumulatedElapsed + activeElapsed)
        return kind == .timer ? min(total, duration) : total
    }

    func remaining(at date: Date) -> TimeInterval {
        guard kind == .timer else { return 0 }
        return max(0, duration - elapsed(at: date))
    }

    mutating func pause(at date: Date) {
        guard phase == .running else { return }
        accumulatedElapsed = elapsed(at: date)
        resumedAt = nil
        phase = .paused
    }

    mutating func resume(at date: Date) {
        guard phase == .paused else { return }
        resumedAt = date
        phase = .running
    }

    mutating func finish() {
        guard kind == .timer else { return }
        accumulatedElapsed = duration
        resumedAt = nil
        phase = .finished
    }
}

enum TimeActivityFormatter {
    static func timer(_ remaining: TimeInterval) -> String {
        formattedWholeSeconds(Int(ceil(max(0, remaining))))
    }

    static func stopwatch(_ elapsed: TimeInterval, includesCentiseconds: Bool) -> String {
        let clamped = max(0, elapsed)
        let wholeSeconds = Int(clamped)
        let hours = wholeSeconds / 3_600
        let minutes = (wholeSeconds % 3_600) / 60
        let seconds = wholeSeconds % 60

        if includesCentiseconds {
            let centiseconds = min(
                99,
                Int(((clamped - floor(clamped)) * 100 + 0.000_001).rounded(.down))
            )
            if hours > 0 {
                return String(
                    format: "%02d:%02d:%02d.%02d",
                    hours,
                    minutes,
                    seconds,
                    centiseconds
                )
            }
            return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
        }

        return formattedWholeSeconds(wholeSeconds)
    }

    private static func formattedWholeSeconds(_ wholeSeconds: Int) -> String {
        let hours = wholeSeconds / 3_600
        let minutes = (wholeSeconds % 3_600) / 60
        let seconds = wholeSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
