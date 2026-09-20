//
//  HomeCalendarGeometryTests.swift
//  boringNotch
//
//  Focused calendar regression checks.
//

import Foundation

@main
enum HomeCalendarGeometryTests {
    static func main() {
        let utc = calendar("UTC")
        let center = date("2026-09-07T12:34:56Z")
        let days = HomeCalendarGeometry.days(centeredOn: center, calendar: utc)
        require(days.count == 7, "The rendered window must contain exactly seven days")
        require(Set(days.map(\.id)).count == 7, "Every day must have a stable, distinct midnight identity")
        require(days[3].id == date("2026-09-07T00:00:00Z"), "The requested date must occupy the middle day")
        require(fixture(days.first).id == date("2026-09-04T00:00:00Z") && fixture(days.last).id == date("2026-09-10T00:00:00Z"),
                "The window must extend three calendar days in each direction")
        require(days.allSatisfy { $0.width == 12 * 96 }, "Empty days show only07–19 at96 points per elapsed hour")
        require(HomeCalendarGeometry.offset(of: center.addingTimeInterval(50 * 60), in: days)
                - HomeCalendarGeometry.offset(of: center, in: days) == 80,
                "A 50-minute class must receive 80 points for readable title wrapping")
        verifyContinuousMapping(days)

        let span = fixture(HomeCalendarGeometry.span(of: days))
        let width = HomeCalendarGeometry.width(of: days)
        require(HomeCalendarGeometry.offset(of: span.start.addingTimeInterval(-1), in: days) == 0,
                "Dates before the window must clamp to its start")
        require(HomeCalendarGeometry.offset(of: span.end.addingTimeInterval(1), in: days) == width,
                "Dates after the window must clamp to its end")
        require(HomeCalendarGeometry.date(at: -1, in: days) == fixture(days.first).visibleInterval.start, "Negative offsets must clamp to the window start")
        require(HomeCalendarGeometry.date(at: width + 1, in: days) == fixture(days.last).visibleInterval.end,
                "Offsets past the window must clamp to its end")
        require(HomeCalendarGeometry.span(of: []) == nil && HomeCalendarGeometry.date(at: 0, in: []) == nil,
                "An empty window has no date interval")
        require(HomeCalendarGeometry.offset(of: center, in: []) == 0, "An empty window has zero offset")
        require(HomeCalendarGeometry.needsRecentering(visibleDate: center, in: []), "An empty window must be initialized")

        require(HomeCalendarGeometry.needsRecentering(visibleDate: days[1].id.addingTimeInterval(-0.001), in: days),
                "Entering the first day must trigger recentering")
        require(!HomeCalendarGeometry.needsRecentering(visibleDate: days[1].id, in: days),
                "The second day start remains inside the safe window")
        require(!HomeCalendarGeometry.needsRecentering(visibleDate: days[5].interval.end.addingTimeInterval(-0.001), in: days),
                "The penultimate day remains inside the safe window")
        require(HomeCalendarGeometry.needsRecentering(visibleDate: days[5].interval.end, in: days),
                "Entering the last day must trigger recentering")
        require(HomeCalendarGeometry.needsRecentering(visibleDate: span.start.addingTimeInterval(-86400), in: days)
                && HomeCalendarGeometry.needsRecentering(visibleDate: span.end.addingTimeInterval(86400), in: days),
                "Dates outside either edge must trigger recentering")

        let newYork = calendar("America/New_York")
        verifyDayLength("2026-03-08T12:00:00-04:00", hours: 23, calendar: newYork)
        verifyDayLength("2026-11-01T12:00:00-05:00", hours: 25, calendar: newYork)
        let firstOneThirty = date("2026-11-01T01:30:00-04:00")
        let secondOneThirty = date("2026-11-01T01:30:00-05:00")
        let autumn = HomeCalendarGeometry.days(centeredOn: date("2026-11-01T12:00:00-05:00"), events: [
            .init(id: "repeated-hour", start: firstOneThirty, end: secondOneThirty.addingTimeInterval(1800))
        ], calendar: newYork)
        require(HomeCalendarGeometry.offset(of: secondOneThirty, in: autumn)
                - HomeCalendarGeometry.offset(of: firstOneThirty, in: autumn) == 96,
                "Repeated local times must retain separate positions one elapsed hour apart")

        let lordHowe = calendar("Australia/Lord_Howe")
        verifyDayLength("2026-10-04T12:00:00+11:00", hours: 23.5, calendar: lordHowe)
        verifyDayLength("2026-04-05T12:00:00+10:30", hours: 24.5, calendar: lordHowe)
        verifyDayLength("2026-09-07T12:00:00+05:45", hours: 24, calendar: calendar("Asia/Kathmandu"))

        for zone in [newYork, lordHowe] {
            for direction in [-1.0, 1.0] {
                verifyRepeatedRecentering(from: center, direction: direction, calendar: zone)
            }
        }
        verifyCroppedHours(calendar: utc)
        verifyDayGaps(calendar: utc)
        verifyCurrentTimeGap(calendar: utc)
        print("Home calendar geometry: all checks passed (cropped 07–19 window, day gaps/current-time centering, early/late/overnight events, reset bounds, DST, inverse mapping, 2,400 scrolling steps).")
    }

    private static func verifyDayLength(_ value: String, hours: Double, calendar: Calendar) {
        let days = HomeCalendarGeometry.days(centeredOn: date(value), calendar: calendar)
        require(days[3].interval.duration == hours * 3600, "Calendar day must preserve its actual duration: \(value)")
        require(days[3].width == 12 * 96, "Default daytime width remains12 local hours when DST changes overnight: \(value)")
        verifyContinuousMapping(days)
    }

    private static func verifyContinuousMapping(_ days: [HomeCalendarGeometry.Day]) {
        var x = 0.0
        for (index, day) in days.enumerated() {
            require(HomeCalendarGeometry.offset(of: day.id, in: days) == x, "Day boundaries must include only the explicit visual gaps")
            if index > 0 {
                require(days[index - 1].interval.end == day.interval.start, "Calendar days must form a contiguous interval")
            }
            for fraction in [0.0, 0.1234567, 0.5, 0.999999] {
                let original = day.visibleInterval.start.addingTimeInterval(day.visibleInterval.duration * fraction)
                let offset = HomeCalendarGeometry.offset(of: original, in: days)
                let restored = fixture(HomeCalendarGeometry.date(at: offset, in: days))
                require(abs(restored.timeIntervalSince(original)) < 0.000001,
                        "Elapsed date-to-offset mapping must round-trip within one microsecond")
            }
            x += day.width
            if index < days.count - 1 { x += HomeCalendarGeometry.daySpacing }
        }
        require(HomeCalendarGeometry.offset(of: fixture(days.last).interval.end, in: days) == x,
                "The document width must equal day widths plus one gap between adjacent days")
    }

    private static func verifyRepeatedRecentering(from start: Date, direction: Double, calendar: Calendar) {
        var days = HomeCalendarGeometry.days(centeredOn: start, calendar: calendar)
        var visibleDate = start
        var recenterCount = 0
        for _ in 0..<600 {
            // Keep walking: seven rendered days must never become the end of the calendar.
            let previous = visibleDate
            let offset = HomeCalendarGeometry.offset(of: visibleDate, in: days) + direction * 6 * 96
            visibleDate = fixture(HomeCalendarGeometry.date(at: offset, in: days))
            let mappedOffset = HomeCalendarGeometry.offset(of: visibleDate, in: days)
            require(mappedOffset - offset >= -0.000001 && mappedOffset - offset <= HomeCalendarGeometry.daySpacing,
                    "Scroll mapping may skip only the visual gap, never a rendered time or the window boundary")
            require(visibleDate.timeIntervalSince(previous) * direction > 0,
                    "Scrolling must advance through cropped nights in the requested direction")
            if HomeCalendarGeometry.needsRecentering(visibleDate: visibleDate, in: days, calendar: calendar) {
                days = HomeCalendarGeometry.days(centeredOn: visibleDate, calendar: calendar)
                let rebasedOffset = HomeCalendarGeometry.offset(of: visibleDate, in: days)
                let restoredLeadingDate = fixture(HomeCalendarGeometry.date(at: rebasedOffset, in: days))
                require(abs(restoredLeadingDate.timeIntervalSince(visibleDate)) < 0.000001,
                        "Rebasing must preserve the viewport leading date without a visible jump")
                require(days.count == 7 && !HomeCalendarGeometry.needsRecentering(visibleDate: visibleDate, in: days),
                        "Recentered windows must remain bounded and put the viewport safely inside")
                recenterCount += 1
            }
        }
        require(recenterCount >= 75, "Scrolling must repeatedly replace the bounded window")

    }


    private static func verifyCroppedHours(calendar: Calendar) {
        let today = date("2026-09-07T12:00:00Z")
        let empty = HomeCalendarGeometry.days(centeredOn: today, calendar: calendar)
        require(empty[3].visibleInterval == DateInterval(start: date("2026-09-07T07:00:00Z"), end: date("2026-09-07T19:00:00Z")),
                "A day with no timed events hides both nights")
        let early = CalendarTimelineGeometry.Interval(id: "early", start: date("2026-09-07T05:15:00Z"), end: date("2026-09-07T06:00:00Z"))
        let late = CalendarTimelineGeometry.Interval(id: "late", start: date("2026-09-08T21:00:00Z"), end: date("2026-09-08T22:15:00Z"))
        let ranged = HomeCalendarGeometry.days(centeredOn: today, events: [early, late], calendar: calendar)
        require(ranged[3].visibleInterval.start == date("2026-09-07T05:00:00Z") && ranged[3].width == 14 * 96,
                "An early class extends only its own day's leading range")
        require(ranged[4].visibleInterval.end == date("2026-09-08T23:00:00Z") && ranged[4].width == 16 * 96,
                "A late class extends only its own day's trailing range")
        verifyContinuousMapping(ranged)
        let seam = HomeCalendarGeometry.offset(of: ranged[3].visibleInterval.end, in: ranged)
        require(HomeCalendarGeometry.date(at: seam, in: ranged) == ranged[4].visibleInterval.start,
                "The visual gap points to the next visible day without adding hidden-night time")
        require(HomeCalendarGeometry.date(at: HomeCalendarGeometry.offset(of: today, in: ranged), in: ranged) == today,
                "Changing loaded ranges preserves a visible time when rebasing offsets")
        let ignored = HomeCalendarGeometry.days(centeredOn: today, events: [
            .init(id: "all-day", start: date("2026-09-07T00:00:00Z"), end: date("2026-09-08T00:00:00Z"), isAllDay: true),
            .init(id: "reminder", start: date("2026-09-07T02:00:00Z"), end: date("2026-09-07T02:00:00Z"), isReminder: true)
        ], calendar: calendar)
        require(ignored == empty, "All-day events and reminders never expose the nights")
        let overnight = HomeCalendarGeometry.days(centeredOn: today, events: [
            .init(id: "overnight", start: date("2026-09-07T23:00:00Z"), end: date("2026-09-08T02:00:00Z"))
        ], calendar: calendar)
        require(overnight[3].visibleInterval.end == overnight[3].interval.end && overnight[4].visibleInterval.start == overnight[4].interval.start,
                "An overnight event extends both intersected day ranges to midnight")
        require(!empty[3].isTimeVisible(date("2026-09-07T06:59:59Z")) && !empty[3].isTimeVisible(date("2026-09-07T19:00:00Z")),
                "The current-time marker is hidden outside the displayed hours")
        require(empty[3].isTimeVisible(date("2026-09-07T07:00:00Z")) && empty[3].isTimeVisible(date("2026-09-07T18:59:59Z")),
                "The current-time marker remains visible inside the displayed hours")
        let leading = HomeCalendarGeometry.offset(of: empty[3].id, in: empty)
        for target in [date("2026-09-06T23:30:00Z"), date("2026-09-07T06:00:00Z"), date("2026-09-07T18:30:00Z"), date("2026-09-07T23:30:00Z")] {
            let offset = HomeCalendarGeometry.viewportOffset(near: target, on: today, viewportWidth: 315, in: empty)
            require(offset >= leading && offset + 315 <= leading + empty[3].width,
                    "Today and initial resets keep the complete viewport inside the requested day")
            let center = fixture(HomeCalendarGeometry.date(at: offset + 157.5, in: empty))
            require(calendar.isDate(center, inSameDayAs: today), "A late Today reset must not select tomorrow")
        }
        require(HomeCalendarGeometry.viewportOffset(near: today, on: today, viewportWidth: 2000, in: empty) == leading,
                "An oversized viewport anchors at the requested day's start")
    }

    private static func verifyDayGaps(calendar: Calendar) {
        let today = date("2026-09-07T12:00:00Z")
        let days = HomeCalendarGeometry.days(centeredOn: today, calendar: calendar)
        require(HomeCalendarGeometry.width(of: []) == 0, "An empty strip has no gap")
        require(HomeCalendarGeometry.width(of: [days[3]]) == days[3].width, "A single day has no trailing gap")
        require(HomeCalendarGeometry.width(of: days) == days.reduce(0) { $0 + $1.width } + 6 * HomeCalendarGeometry.daySpacing,
                "Seven days have exactly six visual gaps")
        let shifted = HomeCalendarGeometry.days(centeredOn: today.addingTimeInterval(86400), calendar: calendar)
        for index in 1..<5 {
            let preceding = days[index]
            let following = days[index + 1]
            let gapStart = HomeCalendarGeometry.offset(of: preceding.id, in: days) + preceding.width
            let nextStart = HomeCalendarGeometry.offset(of: following.id, in: days)
            require(nextStart - gapStart == HomeCalendarGeometry.daySpacing,
                    "Adjacent day ranges must be separated by exactly18 points")
            for fraction in [0.0, 0.25, 0.5, 0.999999] {
                let offset = gapStart + HomeCalendarGeometry.daySpacing * fraction
                require(HomeCalendarGeometry.date(at: offset, in: days) == following.visibleInterval.start,
                        "Every pixel in a gap consistently announces the next visible day")
                let rebased = HomeCalendarGeometry.rebasedOffset(offset, from: days, to: shifted)
                let newNextStart = HomeCalendarGeometry.offset(of: following.id, in: shifted)
                require(abs((nextStart - offset) - (newNextStart - rebased)) < 0.000001,
                        "Recentering preserves the exact leading pixel even when it falls inside a gap")
                let restored = HomeCalendarGeometry.rebasedOffset(rebased, from: shifted, to: days)
                require(abs(restored - offset) < 0.000001, "Gap anchors rebase reversibly in either scroll direction")
            }
            require(HomeCalendarGeometry.date(at: nextStart, in: days) == following.visibleInterval.start,
                    "The first pixel after the gap is exactly the next displayed start time")
            let beforeGap = fixture(HomeCalendarGeometry.date(at: gapStart - 0.01, in: days))
            require(beforeGap < preceding.visibleInterval.end && beforeGap > preceding.visibleInterval.end.addingTimeInterval(-1),
                    "The final rendered instant remains on the preceding day")
            let lateReset = HomeCalendarGeometry.viewportOffset(near: preceding.interval.end, on: preceding.id, viewportWidth: 315, in: days)
            require(lateReset + 315 == gapStart, "A late Today viewport ends before the visual gap")
        }
    }

    private static func verifyCurrentTimeGap(calendar: Calendar) {
        let today = date("2026-09-07T12:00:00Z")
        let days = HomeCalendarGeometry.days(centeredOn: today, calendar: calendar)
        let leading = HomeCalendarGeometry.offset(of: days[3].id, in: days)
        let late = date("2026-09-07T22:58:00Z")
        let early = date("2026-09-07T05:12:00Z")
        require(HomeCalendarGeometry.gapOffset(of: late, in: days) == leading + days[3].width + 9,
                "Hidden evening time appears in the following visual gap")
        require(HomeCalendarGeometry.gapOffset(of: early, in: days) == leading - 9,
                "Hidden morning time appears in the preceding visual gap")
        require(HomeCalendarGeometry.gapOffset(of: today, in: days) == nil,
                "Visible time keeps its ordinary in-day marker")
        require(HomeCalendarGeometry.currentTimeOffset(of: today, in: days) == HomeCalendarGeometry.offset(of: today, in: days),
                "Centering a visible time preserves its accurate elapsed-time position")
        require(HomeCalendarGeometry.currentTimeOffset(of: days[0].id.addingTimeInterval(-1), in: days) == nil,
                "A date outside the loaded window has no current-time marker")
        for now in [early, today, late, date("2026-09-07T19:00:00Z")] {
            let marker = fixture(HomeCalendarGeometry.currentTimeOffset(of: now, in: days))
            let viewport = HomeCalendarGeometry.viewportOffset(near: now, on: today, viewportWidth: 315, in: days, centered: true)
            require(abs(viewport + 157.5 - marker) < 0.000001,
                    "Today centers the actual marker even when it is in an overnight gap")
            require(calendar.isDate(now, inSameDayAs: today), "A marker target retains its actual current-day identity")
        }
        let extended = HomeCalendarGeometry.days(centeredOn: today, events: [
            .init(id: "late", start: date("2026-09-07T22:00:00Z"), end: date("2026-09-07T23:00:00Z"))
        ], calendar: calendar)
        require(HomeCalendarGeometry.gapOffset(of: late, in: extended) == nil,
                "An event that exposes the current time moves the marker out of the gap onto the elapsed-time ruler")
    }

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = fixture(TimeZone(identifier: zone))
        return calendar
    }

    private static func date(_ value: String) -> Date {
        fixture(ISO8601DateFormatter().date(from: value))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}

private func fixture<T>(_ value: T?) -> T {
    guard let value else { fatalError("Missing calendar test fixture") }
    return value
}
