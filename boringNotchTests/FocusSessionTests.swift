//
//  FocusSessionTests.swift
//  boringNotchTests
//
//  The Pomodoro state machine. Driven by an injected `Date` so a 25-minute
//  interval takes microseconds to test, and so the cases that only happen
//  across sleep, a relaunch, or a settings change mid-interval are reachable
//  at all.
//

import XCTest

@testable import boringNotch

final class FocusSessionTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let durations = FocusDurations.default

    private func at(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    // MARK: - Idle

    func testNewSessionIsIdleAndShowsTheFullInterval() {
        let session = FocusSession()

        XCTAssertTrue(session.isIdle)
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.phase, .work)
        XCTAssertEqual(session.remaining(at: start), 25 * 60, "an idle dial shows the whole interval, not zero")
        XCTAssertEqual(session.progress(at: start), 0)
    }

    // MARK: - Counting down

    func testRemainingCountsDownFromTheDeadline() {
        var session = FocusSession()
        session.start(at: start)

        XCTAssertEqual(session.remaining(at: at(1)), 24 * 60)
        XCTAssertEqual(session.progress(at: at(12.5)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(session.remaining(at: at(99)), 0, "never reports negative time")
    }

    func testExpiryIsAtTheDeadlineNotBefore() {
        var session = FocusSession()
        session.start(at: start)

        XCTAssertFalse(session.hasExpired(at: at(24.99)))
        XCTAssertTrue(session.hasExpired(at: at(25)))
    }

    /// The session stores a deadline rather than decrementing a counter, so a
    /// Mac that slept through most of an interval wakes up with the correct
    /// remaining time instead of however many ticks the app managed to run.
    func testTimeKeepsRunningWhileTheAppIsNotTicking() {
        var session = FocusSession()
        session.start(at: start)

        XCTAssertTrue(session.hasExpired(at: at(240)), "slept past the deadline")
        XCTAssertEqual(session.remaining(at: at(240)), 0)
    }

    // MARK: - Phase sequence

    /// The long break belongs after the *fourth* work interval. Reading the
    /// look-ahead after incrementing the counter instead of before put it
    /// after the third.
    func testLongBreakFallsOnTheFourthWorkInterval() {
        var session = FocusSession()
        session.start(at: start)

        var phases: [FocusPhase] = []
        var now = start
        for _ in 0..<8 {
            now = now.addingTimeInterval(session.durations.duration(for: session.phase))
            phases.append(session.advance(at: now, autoStart: true))
        }

        XCTAssertEqual(
            phases,
            [.shortBreak, .work, .shortBreak, .work, .shortBreak, .work, .longBreak, .work]
        )
    }

    func testIntervalsBeforeLongBreakIsConfigurable() {
        var session = FocusSession(
            durations: FocusDurations(work: 60, shortBreak: 60, longBreak: 60, intervalsBeforeLongBreak: 2)
        )
        session.start(at: start)

        XCTAssertEqual(session.advance(at: at(1), autoStart: true), .shortBreak)
        XCTAssertEqual(session.advance(at: at(2), autoStart: true), .work)
        XCTAssertEqual(session.advance(at: at(3), autoStart: true), .longBreak, "every second work interval")
    }

    func testNextPhaseLooksAheadWithoutMutating() {
        var session = FocusSession()
        session.start(at: start)

        XCTAssertEqual(session.nextPhase, .shortBreak)
        XCTAssertEqual(session.nextPhase, .shortBreak, "reading it twice must not advance anything")
        XCTAssertEqual(session.completedWorkIntervals, 0)
    }

    // MARK: - Pause

    func testPausedClockDoesNotDrain() {
        var session = FocusSession()
        session.start(at: start)
        session.pause(at: at(10))

        XCTAssertTrue(session.isPaused)
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.remaining(at: at(10)), 15 * 60)
        XCTAssertEqual(session.remaining(at: at(60)), 15 * 60, "an hour of real time passes; the clock does not move")
    }

    func testResumeRestoresExactlyWhatWasLeft() {
        var session = FocusSession()
        session.start(at: start)
        session.pause(at: at(10))
        session.resume(at: at(60))

        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.remaining(at: at(60)), 15 * 60)
        XCTAssertEqual(session.remaining(at: at(65)), 10 * 60, "and then continues counting down")
    }

    func testToggleCyclesIdleRunningPausedRunning() {
        var session = FocusSession()

        session.toggle(at: start)
        XCTAssertTrue(session.isRunning)
        session.toggle(at: at(1))
        XCTAssertTrue(session.isPaused)
        session.toggle(at: at(2))
        XCTAssertTrue(session.isRunning)
    }

    // MARK: - Skip vs expiry

    /// Pressing Skip should not silently start the break — the user is
    /// choosing to move on, and gets to choose when the next phase begins.
    func testSkipLandsOnTheNextPhaseWithoutStartingIt() {
        var session = FocusSession()
        session.start(at: start)
        session.advance(at: at(5), autoStart: false)

        XCTAssertEqual(session.phase, .shortBreak)
        XCTAssertTrue(session.isIdle)
    }

    func testExpiryCanRollStraightIntoTheNextPhase() {
        var session = FocusSession()
        session.start(at: start)
        session.advance(at: at(25), autoStart: true)

        XCTAssertEqual(session.phase, .shortBreak)
        XCTAssertTrue(session.isRunning)
    }

    // MARK: - Focus total

    func testOnlyCompletedWorkIntervalsCountTowardTheTotal() {
        var session = FocusSession()
        session.start(at: start)

        XCTAssertEqual(session.accumulatedFocus, 0)
        session.advance(at: at(25), autoStart: true)
        XCTAssertEqual(session.accumulatedFocus, 25 * 60, "a finished work interval counts")
        session.advance(at: at(30), autoStart: true)
        XCTAssertEqual(session.accumulatedFocus, 25 * 60, "a finished break does not")
    }

    func testStopResetsTheCycleButKeepsTheDaysTotal() {
        var session = FocusSession()
        session.start(at: start)
        session.advance(at: at(25), autoStart: true)
        session.stop()

        XCTAssertEqual(session.phase, .work)
        XCTAssertTrue(session.isIdle)
        XCTAssertEqual(session.completedWorkIntervals, 0)
        XCTAssertEqual(session.accumulatedFocus, 25 * 60, "time actually spent is not thrown away by Stop")
    }

    // MARK: - Settings changes mid-interval

    /// Halving the work length half-way through should leave half the *new*
    /// length, not subtract ten minutes from the old deadline.
    func testChangingDurationsRebasesProportionally() {
        var session = FocusSession()
        session.start(at: start)

        session.updateDurations(
            FocusDurations(work: 15 * 60, shortBreak: 5 * 60, longBreak: 15 * 60, intervalsBeforeLongBreak: 4),
            at: at(12.5)
        )

        XCTAssertEqual(session.remaining(at: at(12.5)), 7.5 * 60, accuracy: 0.001)
        XCTAssertTrue(session.isRunning, "still running")
    }

    func testChangingDurationsWhilePausedKeepsItPaused() {
        var session = FocusSession()
        session.start(at: start)
        session.pause(at: at(12.5))

        session.updateDurations(
            FocusDurations(work: 50 * 60, shortBreak: 5 * 60, longBreak: 15 * 60, intervalsBeforeLongBreak: 4),
            at: at(12.5)
        )

        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(session.remaining(at: at(99)), 25 * 60, accuracy: 0.001, "half of the new 50 minutes")
    }

    /// These come straight from user settings; a zero would make a phase
    /// expire on the tick it started and spin the state machine.
    func testDegenerateDurationsAreClamped() {
        let durations = FocusDurations(work: 0, shortBreak: -30, longBreak: 1, intervalsBeforeLongBreak: 0)

        XCTAssertGreaterThanOrEqual(durations.work, 60)
        XCTAssertGreaterThanOrEqual(durations.shortBreak, 60)
        XCTAssertGreaterThanOrEqual(durations.longBreak, 60)
        XCTAssertGreaterThanOrEqual(durations.intervalsBeforeLongBreak, 1)
    }

    // MARK: - Restore across a relaunch

    func testRestoreResumesADeadlineStillInTheFuture() {
        let session = FocusSession.restored(
            FocusSession.Persisted(
                phase: .shortBreak, durations: durations, completedWorkIntervals: 2,
                deadline: at(10), accumulatedFocus: 3000
            ),
            now: start
        )

        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.phase, .shortBreak)
        XCTAssertEqual(session.completedWorkIntervals, 2)
        XCTAssertEqual(session.accumulatedFocus, 3000)
    }

    /// The app was not running when this deadline passed, so it never fired.
    /// Resurrecting it would jump the user forward through phases that never
    /// happened.
    func testRestoreDoesNotResurrectADeadlineThatAlreadyPassed() {
        let session = FocusSession.restored(
            FocusSession.Persisted(
                phase: .work, durations: durations, completedWorkIntervals: 2,
                deadline: at(-10), accumulatedFocus: 3000
            ),
            now: start
        )

        XCTAssertTrue(session.isIdle)
        XCTAssertEqual(session.accumulatedFocus, 3000, "the total still survives")
    }

    func testRestoreClampsNegativeStoredValues() {
        let session = FocusSession.restored(
            FocusSession.Persisted(
                phase: .work, durations: durations, completedWorkIntervals: -5,
                deadline: nil, accumulatedFocus: -100
            ),
            now: start
        )

        XCTAssertEqual(session.completedWorkIntervals, 0)
        XCTAssertEqual(session.accumulatedFocus, 0)
    }

    // MARK: - Formatting

    func testCountdownFormatting() {
        XCTAssertEqual(FocusTimeFormatter.countdown(25 * 60), "25:00")
        XCTAssertEqual(FocusTimeFormatter.countdown(65), "1:05")
        XCTAssertEqual(FocusTimeFormatter.countdown(0), "0:00")
        XCTAssertEqual(FocusTimeFormatter.countdown(-5), "0:00", "negatives clamp")
        XCTAssertEqual(FocusTimeFormatter.countdown(3725), "1:02:05", "over an hour")
    }

    /// Rounding up is what stops the display sitting on the same second twice:
    /// at t=0.4s remaining, rounding down would show 0:00 while the timer is
    /// still running.
    func testCountdownRoundsUpSoNoSecondIsShownTwice() {
        XCTAssertEqual(FocusTimeFormatter.countdown(59.4), "1:00")
        XCTAssertEqual(FocusTimeFormatter.countdown(0.2), "0:01")
    }

    func testTotalLabelRoundsDownSoItNeverFlatters() {
        XCTAssertEqual(FocusTimeFormatter.totalLabel(0), "0m")
        XCTAssertEqual(FocusTimeFormatter.totalLabel(59 * 60 + 59), "59m", "59:59 is not an hour")
        XCTAssertEqual(FocusTimeFormatter.totalLabel(120 * 60), "2h")
        XCTAssertEqual(FocusTimeFormatter.totalLabel(135 * 60), "2h 15m")
    }
}
