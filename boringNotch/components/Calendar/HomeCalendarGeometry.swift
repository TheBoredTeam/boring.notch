//
//  HomeCalendarGeometry.swift
//  boringNotch
//
//  Calendar timeline and month presentation.
//

import Foundation

/// A rolling window with one elapsed-time scale and each day's unused nights removed.
enum HomeCalendarGeometry {
    static let pointsPerHour = 96.0
    static let daySpacing = 18.0

    struct Day: Identifiable, Equatable {
        let interval: DateInterval
        let visibleInterval: DateInterval
        let pointsPerHour: Double

        init(interval: DateInterval, visibleInterval: DateInterval? = nil, pointsPerHour: Double = HomeCalendarGeometry.pointsPerHour) {
            self.interval = interval
            self.visibleInterval = visibleInterval ?? interval
            self.pointsPerHour = pointsPerHour
        }

        var id: Date { interval.start }
        var width: Double { visibleInterval.duration / 3600 * pointsPerHour }
        func isTimeVisible(_ date: Date) -> Bool { date >= visibleInterval.start && date < visibleInterval.end }
    }

    static func days(centeredOn date: Date, events: [CalendarTimelineGeometry.Interval] = [], pointsPerHour: Double = pointsPerHour, calendar: Calendar = .current) -> [Day] {
        let center = calendar.startOfDay(for: date)
        return (-3...3).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: center),
                  let interval = calendar.dateInterval(of: .day, for: day) else { return nil }
            return Day(interval: interval, visibleInterval: CalendarTimelineGeometry.visibleRange(in: interval, events: events, calendar: calendar), pointsPerHour: pointsPerHour)
        }
    }

    static func span(of days: [Day]) -> DateInterval? {
        guard let first = days.first, let last = days.last else { return nil }
        return DateInterval(start: first.interval.start, end: last.interval.end)
    }

    static func width(of days: [Day]) -> Double {
        days.reduce(0) { $0 + $1.width } + Double(max(0, days.count - 1)) * daySpacing
    }

    static func offset(of date: Date, in days: [Day]) -> Double {
        var offset = 0.0
        for (index, day) in days.enumerated() {
            if date < day.interval.end {
                return offset + CalendarTimelineGeometry.position(of: date, in: day.visibleInterval, pointsPerHour: day.pointsPerHour)
            }
            offset += day.width
            if index < days.count - 1 { offset += daySpacing }
        }
        return offset
    }

    static func date(at offset: Double, in days: [Day]) -> Date? {
        var remaining = max(0, offset)
        for (index, day) in days.enumerated() {
            if remaining < day.width || index == days.count - 1 {
                return day.visibleInterval.start.addingTimeInterval(min(remaining / day.pointsPerHour * 3600, day.visibleInterval.duration))
            }
            remaining -= day.width
            // A gap announces the next day; it never invents minutes between them.
            if remaining < daySpacing { return days[index + 1].visibleInterval.start }
            remaining -= daySpacing
        }
        return nil
    }

    /// Hidden hours share a visual gap; its midpoint marks now without pretending the gap is a time scale.
    static func gapOffset(of date: Date, in days: [Day]) -> Double? {
        guard let index = days.firstIndex(where: { date >= $0.interval.start && date < $0.interval.end }) else { return nil }
        let day = days[index]
        let leading = offset(of: day.id, in: days)
        if date < day.visibleInterval.start, index > 0 { return leading - daySpacing / 2 }
        if date >= day.visibleInterval.end, index < days.count - 1 { return leading + day.width + daySpacing / 2 }
        return nil
    }

    static func currentTimeOffset(of date: Date, in days: [Day]) -> Double? {
        guard days.contains(where: { date >= $0.interval.start && date < $0.interval.end }) else { return nil }
        return gapOffset(of: date, in: days) ?? offset(of: date, in: days)
    }

    /// Preserve the exact pixel anchor when a rolling window changes, including inside a gap.
    static func rebasedOffset(_ value: Double, from oldDays: [Day], to newDays: [Day]) -> Double {
        guard let date = date(at: value, in: oldDays) else { return 0 }
        return offset(of: date, in: newDays) + value - offset(of: date, in: oldDays)
    }

    /// Reset the whole viewport inside its requested day, even before 07:00 or after 19:00.
    static func viewportOffset(near date: Date, on requestedDay: Date, viewportWidth: Double, in days: [Day], centered: Bool = false) -> Double {
        if centered, let marker = currentTimeOffset(of: date, in: days) {
            return min(max(0, marker - viewportWidth / 2), max(0, width(of: days) - viewportWidth))
        }
        guard let day = days.first(where: { requestedDay >= $0.interval.start && requestedDay < $0.interval.end }) else {
            return offset(of: date, in: days)
        }
        let leading = offset(of: day.interval.start, in: days)
        let local = CalendarTimelineGeometry.position(of: date, in: day.visibleInterval, pointsPerHour: day.pointsPerHour)
        return leading + min(local, max(0, day.width - max(0, viewportWidth)))
    }

    static func needsRecentering(visibleDate: Date, in days: [Day], calendar: Calendar = .current) -> Bool {
        guard days.count >= 3 else { return true }
        return visibleDate < days[1].interval.start || visibleDate >= days[days.count - 2].interval.end
    }
}
