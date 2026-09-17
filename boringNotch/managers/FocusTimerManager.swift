//
//  FocusTimerManager.swift
//  boringNotch
//
//  Owns the running focus session: the tick, the phase transitions, the
//  side effects (blocking, sound, notch nudge) and persistence.
//
//  The rules themselves live in `FocusSession`, which is a pure value type.
//  This class is the part that talks to the clock and the rest of the app.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

@MainActor
final class FocusTimerManager: ObservableObject {
    static let shared = FocusTimerManager()

    @Published private(set) var session: FocusSession
    /// Republished once a second while running so views recompute their
    /// countdown. Views read `remaining(at:)` off this rather than storing
    /// their own copy of the remaining time.
    @Published private(set) var now: Date = .now

    private var tickTask: Task<Void, Never>?
    private var settingsCancellables: Set<AnyCancellable> = []

    private let blocker = DistractionBlocker.shared

    private init() {
        session = FocusSession.restored(
            FocusSession.Persisted(
                phase: Defaults[.focusPhase],
                durations: Self.durationsFromDefaults(),
                completedWorkIntervals: Defaults[.focusCompletedIntervals],
                deadline: Defaults[.focusDeadline],
                accumulatedFocus: Self.accumulatedFocusForToday()
            ),
            now: .now
        )

        // Duration settings apply to a session already in flight, rebased so
        // the proportion elapsed is preserved (see FocusSession).
        for publisher in [
            Defaults.publisher(.focusWorkMinutes).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.focusShortBreakMinutes).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.focusLongBreakMinutes).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.focusIntervalsBeforeLongBreak).map { _ in () }.eraseToAnyPublisher()
        ] {
            publisher.sink { [weak self] in
                Task { @MainActor in self?.applyDurationSettings() }
            }
            .store(in: &settingsCancellables)
        }

        // Toggling a blocking switch mid-session takes effect immediately.
        for publisher in [
            Defaults.publisher(.focusBlockApps).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.focusBlockSites).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.focusBlockedApps).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.focusBlockedSites).map { _ in () }.eraseToAnyPublisher()
        ] {
            publisher.sink { [weak self] in
                Task { @MainActor in self?.applyBlocklist() }
            }
            .store(in: &settingsCancellables)
        }

        if session.isRunning {
            startTicking()
            applyBlocklist()
        }
    }

    // MARK: - Controls

    func toggle() {
        session.toggle(at: .now)
        didChangeRunState()
    }

    func start() {
        session.start(at: .now)
        didChangeRunState()
    }

    func pause() {
        session.pause(at: .now)
        didChangeRunState()
    }

    func stop() {
        session.stop()
        didChangeRunState()
    }

    /// User-initiated skip. Lands on the next phase *paused at its start* so
    /// the user decides when it begins — an automatic roll-on only happens
    /// when a phase genuinely ran out.
    func skip() {
        session.advance(at: .now, autoStart: false)
        didChangeRunState()
    }

    // MARK: - Derived state for views

    var remaining: TimeInterval { session.remaining(at: now) }
    var progress: Double { session.progress(at: now) }

    /// Total focus time today, including the interval currently in progress —
    /// a user watching the number wants it to move while they work, not to
    /// jump 25 minutes when the phase ends.
    var focusToday: TimeInterval {
        guard session.phase == .work, session.isRunning else { return session.accumulatedFocus }
        let elapsed = session.durations.work - remaining
        return session.accumulatedFocus + max(0, elapsed)
    }

    // MARK: - Ticking

    private func didChangeRunState() {
        now = .now
        if session.isRunning {
            startTicking()
            applyBlocklist()
        } else {
            stopTicking()
            // Breaks and pauses are when the user is *allowed* to be
            // distracted; keeping the blocker on through a break would be
            // punitive rather than helpful.
            blocker.stop()
        }
        persist()
    }

    private func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.now = .now
                if self.session.hasExpired(at: self.now) {
                    self.handleExpiry()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func handleExpiry() {
        let finished = session.phase
        // Auto-start only in the direction the user asked for: rolling into a
        // break is the Pomodoro default, but rolling back into work without
        // being asked drags someone back to their desk.
        let autoStart = finished == .work
            ? Defaults[.focusAutoStartBreaks]
            : Defaults[.focusAutoStartWork]

        session.advance(at: now, autoStart: autoStart)
        announce(finished: finished, next: session.phase)
        didChangeRunState()
    }

    /// Announces the transition in the notch and, optionally, with a sound.
    ///
    /// Uses the existing sneak-peek bus rather than posting a user
    /// notification: the whole point of the feature is that the countdown
    /// lives in the notch, so the phase change should land there too.
    private func announce(finished: FocusPhase, next: FocusPhase) {
        NotchUIEventBus.events.send(
            .sneakPeek(
                type: .music,
                value: 0,
                icon: next.systemImage,
                accent: Color.effectiveAccent,
                targetScreenUUID: nil,
                duration: 2.5
            )
        )

        if Defaults[.focusPlaySound] {
            NSSound(named: finished == .work ? "Glass" : "Submarine")?.play()
        }
    }

    // MARK: - Blocking

    private func applyBlocklist() {
        // Only ever enforced during a running *work* phase.
        guard session.isRunning, session.phase == .work else {
            blocker.stop()
            return
        }

        let list = Self.blocklistFromDefaults()
        if blocker.isActive {
            blocker.update(with: list)
        } else {
            blocker.start(with: list)
        }
    }

    private func applyDurationSettings() {
        session.updateDurations(Self.durationsFromDefaults(), at: .now)
        now = .now
        persist()
    }

    // MARK: - Defaults bridging

    static func durationsFromDefaults() -> FocusDurations {
        FocusDurations(
            work: Double(Defaults[.focusWorkMinutes]) * 60,
            shortBreak: Double(Defaults[.focusShortBreakMinutes]) * 60,
            longBreak: Double(Defaults[.focusLongBreakMinutes]) * 60,
            intervalsBeforeLongBreak: Defaults[.focusIntervalsBeforeLongBreak]
        )
    }

    static func blocklistFromDefaults() -> DistractionBlocklist {
        DistractionBlocklist(
            apps: Set(Defaults[.focusBlockedApps].map { BlockedApp(bundleID: $0) }),
            sites: Set(Defaults[.focusBlockedSites].map { BlockedSite(host: $0) }),
            blockApps: Defaults[.focusBlockApps],
            blockSites: Defaults[.focusBlockSites]
        )
    }

    /// The running total resets at midnight: "Focus Time" means today's, and
    /// carrying yesterday's hours forward would quietly inflate it.
    private static func accumulatedFocusForToday() -> TimeInterval {
        guard let stamp = Defaults[.focusAccumulatedDate],
              Calendar.current.isDateInToday(stamp)
        else { return 0 }
        return Defaults[.focusAccumulatedSeconds]
    }

    private func persist() {
        Defaults[.focusPhase] = session.phase
        Defaults[.focusCompletedIntervals] = session.completedWorkIntervals
        Defaults[.focusDeadline] = session.deadline
        Defaults[.focusAccumulatedSeconds] = session.accumulatedFocus
        Defaults[.focusAccumulatedDate] = .now
    }
}
