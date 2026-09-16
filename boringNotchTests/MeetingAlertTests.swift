//
//  MeetingAlertTests.swift
//  boringNotchTests
//
//  Which calendar event the notch surfaces, and when. All of it is pure
//  functions over a supplied Date, so "two minutes before a meeting I haven't
//  declined, unless I dismissed it" is testable without waiting for a real
//  meeting or touching a real calendar.
//

import XCTest

@testable import boringNotch

final class MeetingAlertTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let zoom = MeetingLink(
        url: URL(string: "https://acme.zoom.us/j/123") ?? URL(fileURLWithPath: "/"),
        provider: .zoom
    )

    private func event(
        _ id: String,
        startsIn minutes: Double,
        lasts: Double = 30,
        allDay: Bool = false,
        type: EventType = .event(.accepted),
        link: MeetingLink? = nil
    ) -> EventModel {
        let start = now.addingTimeInterval(minutes * 60)
        return EventModel(
            id: id,
            start: start,
            end: start.addingTimeInterval(lasts * 60),
            title: id,
            location: nil,
            notes: nil,
            url: nil,
            isAllDay: allDay,
            type: type,
            calendar: CalendarModel(
                id: "cal", account: "acct", title: "Work",
                color: .clear, isSubscribed: false, isReminder: false
            ),
            participants: [],
            timeZone: nil,
            hasRecurrenceRules: false,
            priority: nil,
            meetingLink: link
        )
    }

    private func alert(
        _ events: [EventModel],
        policy: MeetingAlertPolicy = .default,
        dismissed: Set<String> = []
    ) -> MeetingAlert? {
        MeetingAlertSelector.alert(from: events, now: now, policy: policy, dismissedEventIDs: dismissed)
    }

    // MARK: - Lead time

    func testMeetingInsideTheLeadTimeIsSurfaced() {
        XCTAssertEqual(alert([event("soon", startsIn: 1.5)])?.eventID, "soon")
    }

    func testMeetingOutsideTheLeadTimeIsNot() {
        XCTAssertNil(alert([event("later", startsIn: 10)]))
    }

    func testExactlyAtTheLeadTimeStillCounts() {
        XCTAssertEqual(alert([event("edge", startsIn: 2)])?.eventID, "edge")
    }

    func testLeadTimeIsConfigurable() {
        let longLead = MeetingAlertPolicy(leadTime: 45 * 60, lingerAfterStart: 5 * 60, requiresMeetingLink: false)
        XCTAssertEqual(alert([event("half-hour", startsIn: 30)], policy: longLead)?.eventID, "half-hour")
    }

    // MARK: - In progress

    func testAMeetingAlreadyRunningKeepsShowing() throws {
        let result = try XCTUnwrap(alert([event("running", startsIn: -3)]))

        XCTAssertEqual(result.eventID, "running")
        guard case .inProgress(let seconds) = result.timing else {
            return XCTFail("expected .inProgress, got \(result.timing)")
        }
        XCTAssertEqual(Int(seconds / 60), 3)
    }

    /// Past the linger window the meeting is either happening (and the user
    /// knows) or was skipped; a permanent banner is just noise.
    func testItStopsShowingAfterTheLingerWindow() {
        XCTAssertNil(alert([event("old", startsIn: -10)]))
    }

    func testAMeetingThatAlreadyEndedIsNotShown() {
        XCTAssertNil(alert([event("ended", startsIn: -3, lasts: 2)]), "ended one minute ago")
    }

    func testTimingReportsMinutesUntilStart() throws {
        let result = try XCTUnwrap(alert([event("soon", startsIn: 1.5)]))

        guard case .startingSoon(let seconds) = result.timing else {
            return XCTFail("expected .startingSoon, got \(result.timing)")
        }
        XCTAssertEqual(Int((seconds / 60).rounded(.up)), 2)
    }

    // MARK: - Filtering

    /// An all-day event has no start time to count down to, and a birthday
    /// does not need a join button.
    func testAllDayEventsAreNeverAlerts() {
        XCTAssertNil(alert([event("allday", startsIn: 1, allDay: true)]))
    }

    func testDeclinedEventsAreDropped() {
        XCTAssertNil(alert([event("nope", startsIn: 1, type: .event(.declined))]))
    }

    func testTentativeAcceptancesStillCount() {
        XCTAssertEqual(alert([event("maybe", startsIn: 1, type: .event(.maybe))])?.eventID, "maybe")
    }

    func testBirthdaysAndRemindersAreNotMeetings() {
        XCTAssertNil(alert([event("bday", startsIn: 1, type: .birthday)]))
        XCTAssertNil(alert([event("todo", startsIn: 1, type: .reminder(completed: false))]))
    }

    func testDismissedEventsStayDismissed() {
        XCTAssertNil(alert([event("seen", startsIn: 1)], dismissed: ["seen"]))
    }

    // MARK: - Join link

    func testAMeetingWithoutALinkStillShowsButCannotBeJoined() throws {
        let result = try XCTUnwrap(alert([event("nolink", startsIn: 1)]))

        XCTAssertEqual(result.eventID, "nolink")
        XCTAssertFalse(result.canJoin, "there is nothing to join, so no Join button is offered")
    }

    func testStrictPolicyOnlySurfacesJoinableMeetings() {
        let strict = MeetingAlertPolicy(leadTime: 120, lingerAfterStart: 300, requiresMeetingLink: true)

        XCTAssertNil(alert([event("nolink", startsIn: 1)], policy: strict))
        XCTAssertEqual(alert([event("withlink", startsIn: 1, link: zoom)], policy: strict)?.eventID, "withlink")
    }

    func testCanJoinReflectsTheLink() throws {
        let result = try XCTUnwrap(alert([event("withlink", startsIn: 1, link: zoom)]))

        XCTAssertTrue(result.canJoin)
        XCTAssertEqual(result.meetingLink?.provider, .zoom)
    }

    // MARK: - Choosing between several

    func testTheSoonestMeetingWins() {
        XCTAssertEqual(alert([event("b", startsIn: 1.9), event("a", startsIn: 0.5)])?.eventID, "a")
    }

    /// You are already late for the one that started; the one in a minute can
    /// wait its turn.
    func testAMeetingAlreadyRunningBeatsOneAboutToStart() {
        XCTAssertEqual(
            alert([event("upcoming", startsIn: 1), event("late", startsIn: -2)])?.eventID,
            "late"
        )
    }

    func testNoEventsMeansNoAlert() {
        XCTAssertNil(alert([]))
    }

    func testAnEmptyCalendarOfIrrelevantEventsMeansNoAlert() {
        let events = [
            event("far", startsIn: 120),
            event("past", startsIn: -600),
            event("allday", startsIn: 1, allDay: true),
            event("declined", startsIn: 1, type: .event(.declined))
        ]

        XCTAssertNil(alert(events))
    }

    // MARK: - Labels

    func testZeroMinuteCasesBothReadAsNow() {
        let aboutToStart = MeetingAlert(
            eventID: "e", title: "t", start: now, end: now, meetingLink: nil,
            timing: .startingSoon(seconds: 0)
        )
        let justStarted = MeetingAlert(
            eventID: "e", title: "t", start: now, end: now, meetingLink: nil,
            timing: .inProgress(seconds: 10)
        )

        XCTAssertEqual(aboutToStart.localizedTiming, justStarted.localizedTiming)
    }

    /// Rounds up, so a meeting 90 seconds away reads "in 2 min" rather than
    /// "in 1 min" — it is closer to two than one, and under-reporting the
    /// time left is the worse error.
    func testStartingSoonRoundsUp() {
        let alert = MeetingAlert(
            eventID: "e", title: "t", start: now, end: now, meetingLink: nil,
            timing: .startingSoon(seconds: 90)
        )

        XCTAssertTrue(alert.localizedTiming.contains("2"), "was \(alert.localizedTiming)")
    }
}
