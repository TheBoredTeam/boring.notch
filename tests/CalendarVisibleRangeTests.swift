//
//  CalendarVisibleRangeTests.swift
//  boringNotch
//

import Foundation

@main
enum CalendarVisibleRangeTests {
    private typealias Geometry = CalendarTimelineGeometry
    private typealias Event = CalendarTimelineGeometry.Interval
    private static var failures: [String] = []
    private static var checks = 0

    static func main() {
        let utc = calendar("UTC")
        let day = day("2026-09-07T12:00:00Z", calendar: utc)
        let defaultRange = Geometry.visibleRange(in: day, events: [], calendar: utc)
        expectRange(defaultRange, "2026-09-07T07:00:00Z", "2026-09-07T19:00:00Z", "Empty day uses local daytime")
        let inside = event("inside", "2026-09-07T09:15:00Z", "2026-09-07T11:45:00Z")
        require(Geometry.visibleRange(in: day, events: [inside], calendar: utc) == defaultRange,
                "Normal events inside daytime must not expand the crop")

        let early = event("early", "2026-09-07T06:30:00Z", "2026-09-07T08:00:00Z")
        let late = event("late", "2026-09-07T20:00:00Z", "2026-09-07T21:15:00Z")
        let expanded = Geometry.visibleRange(in: day, events: [early, late], calendar: utc)
        expectRange(expanded, "2026-09-07T06:00:00Z", "2026-09-07T22:00:00Z", "Events expand to enclosing hours")
        require(Geometry.visibleRange(in: day, events: [late, early], calendar: utc) == expanded,
                "Event fetch order must not change the crop")
        expectRange(Geometry.visibleRange(in: day, events: [event("exact-end", "2026-09-07T20:00:00Z", "2026-09-07T21:00:00Z")], calendar: utc),
                    "2026-09-07T07:00:00Z", "2026-09-07T21:00:00Z", "Exact ending hours must not gain an unnecessary hour")

        let overnight = event("overnight", "2026-09-07T23:30:00Z", "2026-09-08T01:15:00Z")
        expectRange(Geometry.visibleRange(in: day, events: [overnight], calendar: utc),
                    "2026-09-07T07:00:00Z", "2026-09-08T00:00:00Z", "An outgoing overnight event clips to the last day boundary")
        let followingDay = self.day("2026-09-08T12:00:00Z", calendar: utc)
        expectRange(Geometry.visibleRange(in: followingDay, events: [overnight], calendar: utc),
                    "2026-09-08T00:00:00Z", "2026-09-08T19:00:00Z", "An incoming overnight event starts at the first day boundary")
        let spanning = event("spanning", "2026-09-06T22:00:00Z", "2026-09-08T02:00:00Z")
        require(Geometry.visibleRange(in: day, events: [spanning], calendar: utc) == day,
                "A timed event spanning the entire day must retain the complete day")

        let allDay = event("all-day", "2026-09-07T00:00:00Z", "2026-09-08T00:00:00Z", isAllDay: true)
        let reminder = event("reminder", "2026-09-07T04:00:00Z", "2026-09-07T04:00:00Z", isReminder: true)
        let lateReminder = event("late-reminder", "2026-09-07T23:00:00Z", "2026-09-07T23:00:00Z", isReminder: true)
        require(Geometry.visibleRange(in: day, events: [allDay, reminder, lateReminder], calendar: utc) == defaultRange,
                "All-day items and reminders must not expose unused night hours")
        let outside = [
            event("previous", "2026-09-06T20:00:00Z", "2026-09-07T00:00:00Z"),
            event("next", "2026-09-08T00:00:00Z", "2026-09-08T02:00:00Z"),
            event("next-instant", "2026-09-08T00:00:00Z", "2026-09-08T00:00:00Z")
        ]
        require(Geometry.visibleRange(in: day, events: outside, calendar: utc) == defaultRange,
                "Outside events and exclusive midnight boundaries must not change this day")
        let invalid = event("invalid", "2026-09-07T23:00:00Z", "2026-09-07T02:00:00Z")
        require(Geometry.visibleRange(in: day, events: [invalid], calendar: utc) == defaultRange,
                "Malformed negative-duration events must not expand either crop boundary")

        for value in ["2026-09-07T19:00:00Z", "2026-09-07T21:00:00Z", "2026-09-07T23:59:59Z"] {
            let instant = event("instant", value, value)
            let range = Geometry.visibleRange(in: day, events: [instant], calendar: utc)
            require(range.start <= instant.start && range.end > instant.start && range.end <= day.end,
                    "Late point events need a strictly later visible boundary: \(value)")
            let placements = Geometry.layout([instant], in: range)
            require(placements.count == 1 && placements[0].hitWidth > 0,
                    "A late point event must remain selectable after cropping")
        }
        expectRange(Geometry.visibleRange(in: day, events: [event("at-19", "2026-09-07T19:00:00Z", "2026-09-07T19:00:00Z")], calendar: utc),
                    "2026-09-07T07:00:00Z", "2026-09-07T20:00:00Z", "A point event at 19:00 must retain the next enclosing hour")

        verifyDST()
        verifySharedRanges(calendar: utc)
        verifyScrollBounds(defaultRange: defaultRange, expanded: expanded)
        for failure in failures { FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8)) }
        precondition(failures.isEmpty, "\(failures.count) visible-range checks failed")
        print("Calendar visible-range: \(checks) checks passed (night cropping, event boundaries, shared hours, DST, marker and scroll rebasing).")
    }

    private static func verifyDST() {
        let newYork = calendar("America/New_York")
        let spring = day("2026-03-08T12:00:00-04:00", calendar: newYork)
        let autumn = day("2026-11-01T12:00:00-05:00", calendar: newYork)
        require(spring.duration == 23 * 3600 && autumn.duration == 25 * 3600, "DST fixtures must contain 23 and 25 actual hours")
        let springDefault = Geometry.visibleRange(in: spring, events: [], calendar: newYork)
        let autumnDefault = Geometry.visibleRange(in: autumn, events: [], calendar: newYork)
        expectRange(springDefault, "2026-03-08T07:00:00-04:00", "2026-03-08T19:00:00-04:00", "Spring daytime keeps local 07–19")
        expectRange(autumnDefault, "2026-11-01T07:00:00-05:00", "2026-11-01T19:00:00-05:00", "Autumn daytime keeps local 07–19")
        require(springDefault.duration == 12 * 3600 && autumnDefault.duration == 12 * 3600,
                "Daytime crops must remain twelve elapsed hours on both DST dates")
        let springEarly = event("spring-early", "2026-03-08T01:30:00-05:00", "2026-03-08T03:30:00-04:00")
        let springRange = Geometry.visibleRange(in: spring, events: [springEarly], calendar: newYork)
        expectRange(springRange, "2026-03-08T01:00:00-05:00", "2026-03-08T19:00:00-04:00", "Spring early events preserve skipped local hours")
        require(springRange.duration == 17 * 3600, "Spring crop must use actual elapsed duration")
        let autumnEvents = [
            event("first-hour", "2026-11-01T01:15:00-04:00", "2026-11-01T01:45:00-04:00"),
            event("second-hour", "2026-11-01T01:15:00-05:00", "2026-11-01T02:15:00-05:00")
        ]
        let autumnRange = Geometry.visibleRange(in: autumn, events: autumnEvents, calendar: newYork)
        expectRange(autumnRange, "2026-11-01T01:00:00-04:00", "2026-11-01T19:00:00-05:00", "Autumn crop includes both repeated hours")
        let firstX = Geometry.position(of: autumnEvents[0].start, in: autumnRange)
        let secondX = Geometry.position(of: autumnEvents[1].start, in: autumnRange)
        require(secondX - firstX == Geometry.pointsPerHour, "Repeated local times retain distinct horizontal positions")

        let lordHowe = calendar("Australia/Lord_Howe")
        let halfSpring = day("2026-10-04T12:00:00+11:00", calendar: lordHowe)
        let halfAutumn = day("2026-04-05T12:00:00+10:30", calendar: lordHowe)
        require(halfSpring.duration == 23.5 * 3600 && halfAutumn.duration == 24.5 * 3600,
                "Lord Howe fixtures must preserve half-hour DST transitions")
        for halfDay in [halfSpring, halfAutumn] {
            let range = Geometry.visibleRange(in: halfDay, events: [], calendar: lordHowe)
            require(lordHowe.component(.hour, from: range.start) == 7 && lordHowe.component(.hour, from: range.end) == 19
                    && range.duration == 12 * 3600, "Half-hour time changes must not shift local daytime bounds")
        }
        let halfEarly = event("half-early", "2026-10-04T01:45:00+10:30", "2026-10-04T02:45:00+11:00")
        let halfRange = Geometry.visibleRange(in: halfSpring, events: [halfEarly], calendar: lordHowe)
        expectRange(halfRange, "2026-10-04T01:00:00+10:30", "2026-10-04T19:00:00+11:00", "Half-hour spring crop retains the early event")
        require(halfRange.duration == 17.5 * 3600, "Half-hour crop must retain its fractional elapsed duration")

        let springDays = [day("2026-03-07T12:00:00-05:00", calendar: newYork), spring, day("2026-03-09T12:00:00-04:00", calendar: newYork)]
        let sharedSpring = Geometry.sharedVisibleRanges(in: springDays, events: [springEarly], calendar: newYork)
        require(sharedSpring.map(\.duration) == [18 * 3600, 17 * 3600, 18 * 3600],
                "Shared local hours must allow differing elapsed widths across DST")
        require(sharedSpring.allSatisfy { newYork.component(.hour, from: $0.start) == 1 && newYork.component(.hour, from: $0.end) == 19 },
                "Every shared spring row must display the same local start and end hours")
        let autumnDays = [day("2026-10-31T12:00:00-04:00", calendar: newYork), autumn, day("2026-11-02T12:00:00-05:00", calendar: newYork)]
        let sharedAutumn = Geometry.sharedVisibleRanges(in: autumnDays, events: autumnEvents, calendar: newYork)
        require(sharedAutumn[1].start <= autumnEvents[0].start && sharedAutumn[1].end > autumnEvents[1].end,
                "Mapping shared autumn bounds must not drop either repeated-hour event")

        let halfNeighbor = day("2026-10-03T12:00:00+10:30", calendar: lordHowe)
        let atTwo = event("normal-two", "2026-10-03T02:15:00+10:30", "2026-10-03T03:00:00+10:30")
        let afterGap = event("after-gap", "2026-10-04T02:45:00+11:00", "2026-10-04T03:00:00+11:00")
        let sharedGap = Geometry.sharedVisibleRanges(in: [halfNeighbor, halfSpring], events: [atTwo, afterGap], calendar: lordHowe)
        require(sharedGap[0].start == date("2026-10-03T02:00:00+10:30")
                && sharedGap[1].start == date("2026-10-04T02:30:00+11:00"),
                "A shared hour skipped by fractional DST must resolve to the first valid instant on its own day; got \(sharedGap)")
        require(sharedGap[1].start <= afterGap.start, "Resolving a skipped local boundary must preserve its timed event")
        let fullSpring = Event(id: "full-spring", start: spring.start, end: spring.end)
        require(Geometry.sharedVisibleRanges(in: springDays, events: [fullSpring], calendar: newYork) == springDays,
                "Shared midnight bounds must retain each day's own 23- or 24-hour duration")

        let santiago = calendar("America/Santiago")
        let lateRollbackDays = [day("2026-04-03T12:00:00-03:00", calendar: santiago), day("2026-04-04T12:00:00-03:00", calendar: santiago)]
        let firstLateHour = event("late-rollback", "2026-04-04T23:10:00-03:00", "2026-04-04T23:30:00-03:00")
        let sharedRollback = Geometry.sharedVisibleRanges(in: lateRollbackDays, events: [firstLateHour], calendar: santiago)
        require(sharedRollback[0].end == lateRollbackDays[0].end,
                "A repeated late hour must not hide the enclosing midnight boundary on normal neighboring days")
    }

    private static func verifySharedRanges(calendar: Calendar) {
        let days = [day("2026-09-06T12:00:00Z", calendar: calendar), day("2026-09-07T12:00:00Z", calendar: calendar), day("2026-09-08T12:00:00Z", calendar: calendar)]
        require(Geometry.sharedVisibleRanges(in: [], events: [], calendar: calendar).isEmpty, "Empty loaded windows must produce no shared ranges")
        let defaults = Geometry.sharedVisibleRanges(in: days, events: [], calendar: calendar)
        require(defaults.count == days.count && defaults.allSatisfy { $0.duration == 12 * 3600 },
                "Empty loaded days must each retain daytime")
        let early = event("shared-early", "2026-09-06T06:30:00Z", "2026-09-06T07:30:00Z")
        let late = event("shared-late", "2026-09-08T20:45:00Z", "2026-09-08T21:15:00Z")
        for events in [[early], [late], [early, late]] {
            let ranges = Geometry.sharedVisibleRanges(in: days, events: events, calendar: calendar)
            let startHour = events.contains(where: { $0.id == early.id }) ? 6 : 7
            let endHour = events.contains(where: { $0.id == late.id }) ? 22 : 19
            for (day, range) in zip(days, ranges) {
                require(calendar.isDate(range.start, inSameDayAs: day.start)
                        && calendar.component(.hour, from: range.start) == startHour
                        && calendar.component(.hour, from: range.end) == endHour,
                        "Shared hours must apply to every loaded row, including rows without events")
            }
        }
        let overnight = event("shared-overnight", "2026-09-06T23:30:00Z", "2026-09-07T01:15:00Z")
        require(Geometry.sharedVisibleRanges(in: days, events: [overnight], calendar: calendar) == days,
                "Shared overnight boundaries must map midnight and next midnight onto each corresponding day")
        let unloaded = event("unloaded", "2026-09-07T02:00:00Z", "2026-09-07T23:00:00Z")
        let sparseDays = [days[0], days[2]]
        require(Geometry.sharedVisibleRanges(in: sparseDays, events: [unloaded], calendar: calendar)
                == Geometry.sharedVisibleRanges(in: sparseDays, events: [], calendar: calendar),
                "Events on an unloaded intervening day must not expand sparse visible rows")
    }

    private static func verifyScrollBounds(defaultRange: DateInterval, expanded: DateInterval) {
        let afterHours = date("2026-09-07T21:00:00Z")
        let width = defaultRange.duration / 3600 * Geometry.pointsPerHour
        require(Geometry.position(of: afterHours, in: defaultRange) == width, "After-hours Today positioning must clamp to the crop end")
        func markerVisible(_ now: Date) -> Bool { now >= defaultRange.start && now < defaultRange.end }
        require(!markerVisible(afterHours) && !markerVisible(defaultRange.end), "Current-time markers must be absent at and after the exclusive crop end")
        require(markerVisible(defaultRange.start) && markerVisible(date("2026-09-07T12:00:00Z")),
                "Current-time markers remain visible at the crop start and during daytime")
        let visibleDate = date("2026-09-07T10:17:31Z")
        let oldX = Geometry.position(of: visibleDate, in: defaultRange)
        let newX = Geometry.position(of: visibleDate, in: expanded)
        let restoredOld = defaultRange.start.addingTimeInterval(oldX / Geometry.pointsPerHour * 3600)
        let restoredNew = expanded.start.addingTimeInterval(newX / Geometry.pointsPerHour * 3600)
        require(abs(restoredOld.timeIntervalSince(visibleDate)) < 0.000001
                && abs(restoredNew.timeIntervalSince(visibleDate)) < 0.000001,
                "Rebasing a crop with an earlier start must preserve the absolute visible date")
        require(abs(newX - oldX - Geometry.pointsPerHour) < 0.000001,
                "An extra earlier hour must shift the scroll offset by exactly one hour of points")
    }

    private static func event(_ id: String, _ start: String, _ end: String, isAllDay: Bool = false, isReminder: Bool = false) -> Event {
        Event(id: id, start: date(start), end: date(end), isAllDay: isAllDay, isReminder: isReminder)
    }

    private static func expectRange(_ range: DateInterval, _ start: String, _ end: String, _ message: String) {
        require(range.start == date(start) && range.end == date(end), "\(message): got \(range)")
    }

    private static func day(_ value: String, calendar: Calendar) -> DateInterval {
        Geometry.dayInterval(for: date(value), calendar: calendar)
    }

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = unwrap(TimeZone(identifier: zone))
        return calendar
    }

    private static func date(_ value: String) -> Date {
        unwrap(ISO8601DateFormatter().date(from: value))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures.append(message) }
    }
    private static func unwrap<Value>(_ value: Value?, file: StaticString = #file, line: UInt = #line) -> Value {
        guard let value else { preconditionFailure("Missing test fixture", file: file, line: line) }
        return value
    }

}
