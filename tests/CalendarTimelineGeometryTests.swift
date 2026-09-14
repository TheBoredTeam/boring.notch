//
//  CalendarTimelineGeometryTests.swift
//  boringNotch
//

import Foundation

@main
enum CalendarTimelineGeometryTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = unwrap(TimeZone(identifier: "America/New_York"))
        let spring = CalendarTimelineGeometry.dayInterval(for: date("2026-03-08T12:00:00-04:00"), calendar: calendar)
        let autumn = CalendarTimelineGeometry.dayInterval(for: date("2026-11-01T12:00:00-05:00"), calendar: calendar)
        require(spring.duration == 23 * 3600, "Spring day must have 23 elapsed hours")
        require(autumn.duration == 25 * 3600, "Autumn day must have 25 elapsed hours")
        let autumnTicks = CalendarTimelineGeometry.hourTicks(in: autumn)
        require(autumnTicks.filter { calendar.component(.hour, from: $0) == 1 }.count == 2,
                "Both repeated autumn hours must appear")
        require(CalendarTimelineGeometry.position(of: date("2026-11-01T01:30:00-05:00"), in: autumn) == 2.5 * 92,
                "Second 01:30 must have its own position")
        require(CalendarTimelineGeometry.position(of: date("2026-03-08T03:00:00-04:00"), in: spring) == 2 * 92,
                "Spring 03:00 follows two elapsed hours")

        calendar.timeZone = unwrap(TimeZone(identifier: "Australia/Lord_Howe"))
        let halfHourDay = CalendarTimelineGeometry.dayInterval(for: date("2026-10-04T12:00:00+11:00"), calendar: calendar)
        require(halfHourDay.duration == 23.5 * 3600, "Half-hour DST transitions must be preserved")
        require(CalendarTimelineGeometry.hourTicks(in: halfHourDay).last == halfHourDay.end,
                "Fractional-hour day must include its ending boundary")

        calendar.timeZone = unwrap(TimeZone(secondsFromGMT: 0))
        let day = CalendarTimelineGeometry.dayInterval(for: date("2026-09-07T12:00:00Z"), calendar: calendar)
        let intervals: [CalendarTimelineGeometry.Interval] = [
            .init(id: "midnight", start: date("2026-09-06T23:30:00Z"), end: date("2026-09-07T01:00:00Z")),
            .init(id: "long", start: date("2026-09-07T09:00:00Z"), end: date("2026-09-07T11:00:00Z")),
            .init(id: "overlap", start: date("2026-09-07T10:00:00Z"), end: date("2026-09-07T12:00:00Z")),
            .init(id: "adjacent", start: date("2026-09-07T12:00:00Z"), end: date("2026-09-07T13:00:00Z")),
            .init(id: "short", start: date("2026-09-07T14:00:00Z"), end: date("2026-09-07T14:01:00Z")),
            .init(id: "short-neighbor", start: date("2026-09-07T14:02:00Z"), end: date("2026-09-07T14:03:00Z")),
            .init(id: "instant", start: date("2026-09-07T15:00:00Z"), end: date("2026-09-07T15:00:00Z")),
            .init(id: "ends-midnight", start: date("2026-09-06T23:00:00Z"), end: day.start),
            .init(id: "next-day", start: day.end, end: day.end.addingTimeInterval(3600)),
            .init(id: "invalid", start: day.start.addingTimeInterval(3600), end: day.start)
        ]
        let result = CalendarTimelineGeometry.layout(intervals, in: day)
        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        require(result.count == 7, "Exclusive midnight boundary and invalid intervals must be excluded")
        require(unwrap(byID["midnight"]).x == 0 && unwrap(byID["midnight"]).width == 92, "Overnight event must clip to this day")
        require(unwrap(byID["long"]).width == 184, "Duration must determine exact block width")
        require(unwrap(byID["long"]).lane != unwrap(byID["overlap"]).lane, "Overlaps must use separate lanes")
        require(unwrap(byID["adjacent"]).lane == 0, "Finished lanes must be reused")
        require(abs(unwrap(byID["short"]).width - 92 / 60) < 0.0001 && unwrap(byID["short"]).hitWidth == 24,
                "Short event needs exact visible duration and a larger invisible hit target")
        require(unwrap(byID["short"]).lane != unwrap(byID["short-neighbor"]).lane, "Short event hit targets must not collide")
        require(unwrap(byID["instant"]).width == 0 && unwrap(byID["instant"]).hitWidth == 24, "Instant event must remain selectable")
        require(CalendarTimelineGeometry.position(of: day.start.addingTimeInterval(-60), in: day) == 0,
                "Elapsed progress must clamp before the day")
        require(CalendarTimelineGeometry.position(of: day.end.addingTimeInterval(60), in: day) == 24 * 92,
                "Elapsed progress must clamp after the day")
        let reversed = CalendarTimelineGeometry.layout(intervals.reversed(), in: day)
        require(result.map { "\($0.id)-\($0.lane)" } == reversed.map { "\($0.id)-\($0.lane)" },
                "Layout must be deterministic regardless of fetch ordering")
        require(result.allSatisfy { $0.hitX >= 0 && $0.hitX + $0.hitWidth <= 24 * 92 },
                "Every selectable target must remain within the scrollable day")
        let compact = CalendarTimelineGeometry.layout(intervals, in: day, pointsPerHour: 54)
        let compactByID = Dictionary(uniqueKeysWithValues: compact.map { ($0.id, $0) })
        require(compact.count == result.count, "Compact layout must preserve every visible event")
        require(unwrap(compactByID["long"]).width == 108, "Compact blocks must use the compact hour scale")
        require(abs(unwrap(compactByID["short"]).width - 0.9) < 0.0001 && unwrap(compactByID["short"]).hitWidth == 24,
                "Compact short events retain full pointer targets without inflated durations")
        require(unwrap(compactByID["short"]).lane != unwrap(compactByID["short-neighbor"]).lane,
                "Compact hit targets still require collision-free lanes")
        require(CalendarTimelineGeometry.position(of: date("2026-11-01T01:30:00-05:00"), in: autumn, pointsPerHour: 54) == 2.5 * 54,
                "Compact current-time position must use elapsed DST time and compact scale")
        let laneCounts = CalendarTimelineGeometry.clusterLaneCounts(for: result)
        require(laneCounts["long"] == 2 && laneCounts["overlap"] == 2,
                "Intersecting events must share a two-lane cluster")
        require(laneCounts["adjacent"] == 1 && laneCounts["instant"] == 1,
                "Later independent events must regain the full row height")
        require(laneCounts["short"] == 2 && laneCounts["short-neighbor"] == 2,
                "Expanded short-event targets must participate in overlap clusters")
        require(CalendarTimelineGeometry.clusterLaneCounts(for: []).isEmpty,
                "An empty day has no overlap clusters")
        print("Calendar timeline geometry: 28 checks passed (full/compact scales, DST, midnight, overlap clusters, short targets, progress).")
    }

    private static func date(_ value: String) -> Date {
        unwrap(ISO8601DateFormatter().date(from: value))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    private static func unwrap<Value>(_ value: Value?, file: StaticString = #file, line: UInt = #line) -> Value {
        guard let value else { preconditionFailure("Missing test fixture", file: file, line: line) }
        return value
    }

}
