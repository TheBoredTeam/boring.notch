//
//  CalendarTimelineGeometry.swift
//  boringNotch
//

import Foundation

/// All positions use elapsed time within a calendar day, including 23- and 25-hour days.
enum CalendarTimelineGeometry {
    static let pointsPerHour = 92.0
    static let minimumHitWidth = 24.0

    struct Interval {
        let id: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let isReminder: Bool

        init(id: String, start: Date, end: Date, isAllDay: Bool = false, isReminder: Bool = false) {
            self.id = id
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
            self.isReminder = isReminder
        }
    }

    struct Placement: Identifiable {
        let id: String
        let x: Double
        let width: Double
        let hitX: Double
        let hitWidth: Double
        let lane: Int
    }

    static func dayInterval(for date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    /// Show local daytime by default, retaining the hours needed for timed events.
    static func visibleRange(in day: DateInterval, events: [Interval], calendar: Calendar = .current) -> DateInterval {
        var start = localBoundary(at: 7 * 60, in: day, calendar: calendar)
        var end = localBoundary(at: 19 * 60, in: day, calendar: calendar)
        for event in events where !event.isAllDay && !event.isReminder && event.end >= event.start {
            let instant = event.start == event.end
            guard event.start < day.end,
                  event.end > day.start || (instant && event.start >= day.start) else { continue }
            let clippedStart = max(event.start, day.start)
            let clippedEnd = min(event.end, day.end)
            if clippedStart < start {
                let hour = calendar.component(.hour, from: clippedStart)
                let roundedStart = localBoundary(at: hour * 60, in: day, calendar: calendar)
                start = max(day.start, min(clippedStart, roundedStart))
            }
            if clippedEnd > end || (instant && clippedEnd >= end) {
                // A point event at the right boundary still needs a visible hit target.
                let effectiveEnd = instant ? min(day.end, clippedEnd.addingTimeInterval(1)) : clippedEnd
                let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: effectiveEnd)
                let exactHour = time.minute == 0 && time.second == 0 && time.nanosecond == 0
                let nextHour = (time.hour ?? 23) + 1
                // Round the wall clock, not a 3,600-second bucket: some DST changes last half an hour.
                let roundedEnd = exactHour ? effectiveEnd : localBoundary(at: nextHour * 60, in: day, calendar: calendar)
                end = min(day.end, max(effectiveEnd, roundedEnd))
            }
        }
        return DateInterval(start: max(day.start, start), end: min(day.end, end))
    }

    /// Stacked days share the same local hour bounds, even when their dates differ.
    static func sharedVisibleRanges(in days: [DateInterval], events: [Interval], calendar: Calendar = .current) -> [DateInterval] {
        let ranges = days.map { visibleRange(in: $0, events: events, calendar: calendar) }
        func minuteOfDay(_ date: Date, day: DateInterval) -> Int {
            if date >= day.end { return 24 * 60 }
            let time = calendar.dateComponents([.hour, .minute], from: date)
            return (time.hour ?? 0) * 60 + (time.minute ?? 0)
        }
        guard let firstMinute = zip(days, ranges).map({ minuteOfDay($0.1.start, day: $0.0) }).min(),
              let lastMinute = zip(days, ranges).map({ minuteOfDay($0.1.end, day: $0.0) }).max() else { return [] }
        return zip(days, ranges).map { day, ownRange in
            // Keep actual occurrences included through repeated or skipped local hours.
            return DateInterval(start: max(day.start, min(localBoundary(at: firstMinute, in: day, calendar: calendar), ownRange.start)),
                                end: min(day.end, max(localBoundary(at: lastMinute, in: day, calendar: calendar), ownRange.end)))
        }
    }

    private static func localBoundary(at minute: Int, in day: DateInterval, calendar: Calendar) -> Date {
        if minute == 0 { return day.start }
        if minute >= 24 * 60 { return day.end }
        var components = calendar.dateComponents([.era, .year, .month, .day], from: day.start)
        components.hour = minute / 60
        components.minute = minute % 60
        components.second = 0
        // Construct on this date: searching for a missing hour can jump to tomorrow.
        return calendar.date(from: components) ?? day.start
    }

    static func position(of date: Date, in day: DateInterval, pointsPerHour: Double = pointsPerHour) -> Double {
        min(max(date.timeIntervalSince(day.start), 0), day.duration) / 3600 * pointsPerHour
    }

    struct HourLabel: Identifiable {
        let id: Date
        let x: Double
        let width: Double
    }

    /// Pack measured labels without shrinking text, including cropped endpoints and DST suffixes.
    static func hourLabels(in day: DateInterval, pointsPerHour: Double, widths: [Double],
                           avoiding exclusions: [Range<Double>] = []) -> [HourLabel] {
        let ticks = hourTicks(in: day)
        let totalWidth = day.duration / 3600 * pointsPerHour
        let candidates = zip(ticks, widths).map { tick, width in
            HourLabel(id: tick, x: min(max(0, position(of: tick, in: day, pointsPerHour: pointsPerHour) + 4),
                                      max(0, totalWidth - width)), width: width)
        }.filter { label in
            label.width <= totalWidth && !exclusions.contains { $0.overlaps((label.x - 4)..<(label.x + label.width + 4)) }
        }
        // The end of the day gets a seat before the remaining labels line up.
        guard let last = candidates.last else { return [] }
        var result: [HourLabel] = []
        var previousEnd = -Double.infinity
        for label in candidates.dropLast() where label.x >= previousEnd + 6 && label.x + label.width + 6 <= last.x {
            result.append(label)
            previousEnd = label.x + label.width
        }
        result.append(last)
        return result
    }

    static func hourTicks(in day: DateInterval) -> [Date] {
        // Advancing actual hours preserves both occurrences of a repeated autumn hour.
        var ticks = stride(from: 0.0, through: day.duration, by: 3600).map {
            day.start.addingTimeInterval($0)
        }
        if ticks.last != day.end { ticks.append(day.end) }
        return ticks
    }

    static func layout(_ intervals: [Interval], in day: DateInterval, pointsPerHour: Double = pointsPerHour) -> [Placement] {
        let dayWidth = day.duration / 3600 * pointsPerHour
        var laneEnds: [Double] = []
        return intervals
            .filter {
                $0.start < day.end && $0.end >= $0.start &&
                    ($0.end > day.start || ($0.start == $0.end && $0.start >= day.start))
            }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.end != $1.end { return $0.end > $1.end }
                return $0.id < $1.id
            }
            .map { interval in
                let x = position(of: interval.start, in: day, pointsPerHour: pointsPerHour)
                let width = position(of: interval.end, in: day, pointsPerHour: pointsPerHour) - x
                let hitWidth = min(max(width, minimumHitWidth), dayWidth)
                let hitX = max(0, min(x - (hitWidth - width) / 2, dayWidth - hitWidth))
                // Tiny meetings get a usable target, without pretending they last longer.
                let lane = laneEnds.firstIndex(where: { $0 <= hitX }) ?? laneEnds.count
                if lane == laneEnds.count {
                    laneEnds.append(hitX + hitWidth)
                } else {
                    laneEnds[lane] = hitX + hitWidth
                }
                return Placement(id: interval.id, x: x, width: width,
                                 hitX: hitX, hitWidth: hitWidth, lane: lane)
            }
    }

    /// Independent overlap clusters can each use the full available row height.
    static func clusterLaneCounts(for placements: [Placement]) -> [String: Int] {
        var counts: [String: Int] = [:]
        var cluster: [Placement] = []
        var clusterEnd = -Double.infinity
        func finishCluster() {
            let count = (cluster.map(\.lane).max() ?? 0) + 1
            for placement in cluster { counts[placement.id] = count }
        }
        for placement in placements.sorted(by: { $0.hitX < $1.hitX }) {
            if placement.hitX >= clusterEnd {
                finishCluster()
                cluster = []
                clusterEnd = -Double.infinity
            }
            cluster.append(placement)
            clusterEnd = max(clusterEnd, placement.hitX + placement.hitWidth)
        }
        finishCluster()
        return counts
    }
}

/// Horizontal density changes time geometry, never the event typography.
enum CalendarTimelineScale {
    static let range = 0.0...2.5

    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : 1
    }

    static func pointsPerHour(for value: Double, fitting viewportWidth: Double = 0, duration: TimeInterval = 12 * 3600) -> Double {
        let fit = duration > 0 && viewportWidth > 0 ? viewportWidth / (duration / 3600) : (value <= 0 ? 96 : 0)
        return max(fit, 96 * clamped(value))
    }
}
