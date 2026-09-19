//
//  FocusSession.swift
//  boringNotch
//
//  The Pomodoro state machine behind the notch's focus timer.
//
//  Deliberately a plain value type driven by an injected `Date`: no timers, no
//  singletons, no Combine. Everything that decides what the timer *is* —
//  which phase comes next, how much is left, when a long break is due, what
//  pausing does to the clock — is therefore reachable from a test without
//  waiting 25 minutes for one.
//
//  `FocusTimerManager` owns the ticking and the side effects.
//

import Foundation

/// What the session is currently doing.
enum FocusPhase: String, Equatable, Sendable {
    case work
    case shortBreak
    case longBreak

    var isBreak: Bool { self != .work }

    var localizedTitle: String {
        switch self {
        case .work:
            return NSLocalizedString("focus_phase_work", comment: "Focus timer phase: a work interval")
        case .shortBreak:
            return NSLocalizedString("focus_phase_short_break", comment: "Focus timer phase: a short break")
        case .longBreak:
            return NSLocalizedString("focus_phase_long_break", comment: "Focus timer phase: a long break")
        }
    }

    var systemImage: String {
        switch self {
        case .work: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "figure.walk"
        }
    }
}

/// How long each phase runs, and how often a long break is due.
struct FocusDurations: Equatable, Sendable {
    var work: TimeInterval
    var shortBreak: TimeInterval
    var longBreak: TimeInterval
    /// Work intervals completed before a long break replaces a short one.
    /// The classic Pomodoro figure is 4.
    var intervalsBeforeLongBreak: Int

    static let `default` = FocusDurations(
        work: 25 * 60,
        shortBreak: 5 * 60,
        longBreak: 15 * 60,
        intervalsBeforeLongBreak: 4
    )

    /// Clamped on the way in rather than trusted: these come from user
    /// settings, and a zero or negative duration would make a phase end on
    /// the same tick it started and spin the state machine.
    init(work: TimeInterval, shortBreak: TimeInterval, longBreak: TimeInterval, intervalsBeforeLongBreak: Int) {
        self.work = max(60, work)
        self.shortBreak = max(60, shortBreak)
        self.longBreak = max(60, longBreak)
        self.intervalsBeforeLongBreak = max(1, intervalsBeforeLongBreak)
    }

    func duration(for phase: FocusPhase) -> TimeInterval {
        switch phase {
        case .work: return work
        case .shortBreak: return shortBreak
        case .longBreak: return longBreak
        }
    }
}

/// A running (or paused) focus session.
struct FocusSession: Equatable, Sendable {
    private(set) var phase: FocusPhase
    private(set) var durations: FocusDurations
    /// Work intervals finished so far in this run. Drives long-break timing
    /// and the "Focus Time" total.
    private(set) var completedWorkIntervals: Int

    /// When the current phase ends, if running. Storing a deadline rather than
    /// counting down a stored remainder means the timer stays correct across a
    /// missed tick, an app hang, or the Mac sleeping — the clock is the source
    /// of truth, not our tick count.
    private(set) var deadline: Date?
    /// Set only while paused; the deadline is reconstructed from it on resume.
    private(set) var pausedRemaining: TimeInterval?

    /// Total time actually spent in completed work phases.
    private(set) var accumulatedFocus: TimeInterval

    var isRunning: Bool { deadline != nil }
    var isPaused: Bool { pausedRemaining != nil }
    /// Neither running nor paused — the state the dial shows "Start" in.
    var isIdle: Bool { !isRunning && !isPaused }

    init(durations: FocusDurations = .default) {
        self.phase = .work
        self.durations = durations
        self.completedWorkIntervals = 0
        self.deadline = nil
        self.pausedRemaining = nil
        self.accumulatedFocus = 0
    }

    // MARK: - Derived

    /// Seconds left in the current phase, never negative.
    ///
    /// An idle session reports the full phase duration so the dial renders a
    /// complete ring with "25 min" under the Start button rather than zero.
    func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return max(0, pausedRemaining) }
        guard let deadline else { return durations.duration(for: phase) }
        return max(0, deadline.timeIntervalSince(now))
    }

    /// Progress through the current phase, 0...1.
    func progress(at now: Date) -> Double {
        let total = durations.duration(for: phase)
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: now) / total))
    }

    func hasExpired(at now: Date) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    /// Which phase follows the current one.
    ///
    /// A work interval is followed by a long break every
    /// `intervalsBeforeLongBreak`-th time; any break returns to work.
    var nextPhase: FocusPhase {
        guard phase == .work else { return .work }
        let completed = completedWorkIntervals + 1
        return completed % durations.intervalsBeforeLongBreak == 0 ? .longBreak : .shortBreak
    }

    // MARK: - Transitions

    mutating func start(at now: Date) {
        guard isIdle else { return }
        deadline = now.addingTimeInterval(durations.duration(for: phase))
        pausedRemaining = nil
    }

    mutating func pause(at now: Date) {
        guard let deadline else { return }
        pausedRemaining = max(0, deadline.timeIntervalSince(now))
        self.deadline = nil
    }

    mutating func resume(at now: Date) {
        guard let pausedRemaining else { return }
        deadline = now.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
    }

    mutating func toggle(at now: Date) {
        if isRunning { pause(at: now) } else if isPaused { resume(at: now) } else { start(at: now) }
    }

    /// Ends the whole session and returns to an idle work phase.
    ///
    /// `accumulatedFocus` is kept: it is the "Focus Time" total for the day,
    /// and zeroing it on stop would throw away time the user actually spent.
    mutating func stop() {
        phase = .work
        deadline = nil
        pausedRemaining = nil
        completedWorkIntervals = 0
    }

    /// Ends the current phase and moves to the next one.
    ///
    /// `autoStart` is what separates an expiry that rolls straight into a
    /// break from a user pressing Skip, which lands on a paused-at-the-start
    /// next phase so they choose when it begins.
    @discardableResult
    mutating func advance(at now: Date, autoStart: Bool) -> FocusPhase {
        // Read the look-ahead *before* incrementing: `nextPhase` already
        // counts the in-flight interval, so asking after the increment
        // double-counts it and the long break lands one interval early.
        let next = nextPhase

        if phase == .work {
            completedWorkIntervals += 1
            accumulatedFocus += durations.work
        }

        phase = next
        pausedRemaining = nil
        deadline = autoStart ? now.addingTimeInterval(durations.duration(for: phase)) : nil
        return phase
    }

    /// Applies new durations mid-session.
    ///
    /// Changing settings must not silently extend a phase that is already
    /// running — the deadline is rebased so the *proportion* elapsed is
    /// preserved, which is what a user who shortens "work" from 25 to 15
    /// minutes half-way through expects to see.
    mutating func updateDurations(_ new: FocusDurations, at now: Date) {
        let elapsedFraction = progress(at: now)
        durations = new

        let total = new.duration(for: phase)
        let remaining = total * (1 - elapsedFraction)

        if isRunning {
            deadline = now.addingTimeInterval(remaining)
        } else if isPaused {
            pausedRemaining = remaining
        }
    }

    /// What gets written to preferences so a session survives a relaunch.
    ///
    /// A struct rather than a long parameter list: these five values are one
    /// thing — the saved session — and naming them as a type keeps the
    /// restore call readable at both ends.
    struct Persisted: Equatable, Sendable {
        var phase: FocusPhase
        var durations: FocusDurations
        var completedWorkIntervals: Int
        var deadline: Date?
        var accumulatedFocus: TimeInterval
    }

    /// Restores a session persisted across a relaunch.
    ///
    /// A deadline that has already passed is *not* resurrected as a running
    /// phase — the app was not there to fire it, and silently jumping the
    /// user several phases forward would be worse than starting fresh.
    static func restored(_ persisted: Persisted, now: Date) -> FocusSession {
        var session = FocusSession(durations: persisted.durations)
        session.phase = persisted.phase
        session.completedWorkIntervals = max(0, persisted.completedWorkIntervals)
        session.accumulatedFocus = max(0, persisted.accumulatedFocus)
        if let deadline = persisted.deadline, deadline > now {
            session.deadline = deadline
        }
        return session
    }
}

// MARK: - Formatting

enum FocusTimeFormatter {
    /// "24:59" — the countdown on the dial. Minutes are not zero-padded
    /// because a leading zero on a 5-minute break reads like a stopwatch.
    static func countdown(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// "25 min" — the phase length shown under an idle dial.
    static func minutesLabel(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        return String(
            format: NSLocalizedString("focus_minutes_short", comment: "A duration in minutes, e.g. '25 min'"),
            minutes
        )
    }

    /// "0m", "45m", "2h 15m" — the running Focus Time total.
    ///
    /// Rounds *down*: claiming an hour of focus after 59 minutes would be
    /// flattering rather than accurate.
    static func totalLabel(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(max(0, interval) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return String(format: NSLocalizedString("duration_minutes", comment: "A duration under an hour, e.g. '45m'"), minutes)
        }
        if minutes == 0 {
            return String(format: NSLocalizedString("duration_hours", comment: "A whole number of hours, e.g. '2h'"), hours)
        }
        return String(format: NSLocalizedString("duration_hours_minutes", comment: "A duration of hours and minutes, e.g. '2h 15m'"), hours, minutes)
    }
}
