//
//  CalendarEmptyDayContent.swift
//  boringNotch
//
//  Created by adamly218 on 09/11/2026.
//

import Defaults
import Foundation

/// What the calendar shows under the date picker when the selected day has no events.
enum CalendarEmptyDayContent: String, CaseIterable, Identifiable, Defaults.Serializable {
    /// "No events today / Enjoy your free time!" — the original behavior.
    case noEventsMessage
    case weather
    case nextEvent
    case dayProgress
    case worldClock
    case sunriseSunset

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .noEventsMessage: String(localized: "\"No events\" message")
        case .weather: String(localized: "Weather")
        case .nextEvent: String(localized: "Next event")
        case .dayProgress: String(localized: "Day progress")
        case .worldClock: String(localized: "World clock")
        case .sunriseSunset: String(localized: "Sunrise & sunset")
        }
    }

    /// Options that read the forecast for `calendarWeatherPlace`.
    var needsForecast: Bool {
        self == .weather || self == .sunriseSunset
    }
}

/// A city picked in Settings from the built-in list (see `City`).
struct CalendarPlace: Codable, Equatable, Sendable, Defaults.Serializable {
    var name: String
    /// Country name, shown in Settings.
    var detail: String
    var latitude: Double
    var longitude: Double
    /// IANA identifier, e.g. "Asia/Tokyo".
    var timeZoneIdentifier: String

    var timeZone: TimeZone? { TimeZone(identifier: timeZoneIdentifier) }

    var displayName: String {
        detail.isEmpty ? name : "\(name), \(detail)"
    }
}

// MARK: - Day progress

/// Week number, day of year and how much of the day has passed.
struct DayProgress: Equatable {
    let weekOfYear: Int
    let dayOfYear: Int
    let daysInYear: Int
    /// 0…1 for today; nil for any other day.
    let fractionOfDayElapsed: Double?

    init(for day: Date, now: Date = Date(), calendar: Calendar = .current) {
        weekOfYear = calendar.component(.weekOfYear, from: day)
        dayOfYear = calendar.ordinality(of: .day, in: .year, for: day) ?? 1
        daysInYear = calendar.range(of: .day, in: .year, for: day)?.count ?? 365

        if calendar.isDate(day, inSameDayAs: now),
           let interval = calendar.dateInterval(of: .day, for: now),
           interval.duration > 0 {
            let elapsed = now.timeIntervalSince(interval.start) / interval.duration
            fractionOfDayElapsed = min(max(elapsed, 0), 1)
        } else {
            fractionOfDayElapsed = nil
        }
    }
}

// MARK: - World clock

enum WorldClock {
    /// Seconds the place is ahead of the local time zone (negative when behind).
    static func offset(of remote: TimeZone, from local: TimeZone = .current, at date: Date = Date()) -> Int {
        remote.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
    }

    /// "Same time", "3 h ahead", "5 h 30 min behind".
    static func offsetDescription(seconds: Int) -> String {
        guard seconds != 0 else { return String(localized: "Same time as here") }
        let minutes = abs(seconds) / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        let amount: String
        if remainder == 0 {
            amount = String(localized: "\(hours) h")
        } else if hours == 0 {
            amount = String(localized: "\(remainder) min")
        } else {
            amount = String(localized: "\(hours) h \(remainder) min")
        }
        return seconds > 0
            ? String(localized: "\(amount) ahead")
            : String(localized: "\(amount) behind")
    }
}

// MARK: - Next event

enum NextEventFinder {
    /// The first event that hasn't ended by `date`. All-day events are skipped when the
    /// user hides them in the list; completed reminders are never "next".
    static func firstUpcoming(in events: [EventModel], after date: Date, hideAllDay: Bool) -> EventModel? {
        events
            .filter { event in
                if event.isAllDay && hideAllDay { return false }
                if case .reminder(let completed) = event.type, completed { return false }
                return event.end > date
            }
            .min { $0.start < $1.start }
    }

    /// Whole calendar days from `now` to `date`: 0 = today, 1 = tomorrow.
    static func daysAway(_ date: Date, from now: Date = Date(), calendar: Calendar = .current) -> Int {
        let from = calendar.startOfDay(for: now)
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    static func daysAwayDescription(_ days: Int) -> String {
        switch days {
        case ..<1: String(localized: "Today")
        case 1: String(localized: "Tomorrow")
        default: String(localized: "In \(days) days")
        }
    }
}

// MARK: - Sunrise & sunset

enum DaylightStatus: Equatable {
    case beforeSunrise(TimeInterval)
    case daylightLeft(TimeInterval)
    case afterSunset

    init(now: Date, sunrise: Date, sunset: Date) {
        if now < sunrise {
            self = .beforeSunrise(sunrise.timeIntervalSince(now))
        } else if now < sunset {
            self = .daylightLeft(sunset.timeIntervalSince(now))
        } else {
            self = .afterSunset
        }
    }

    /// "2 h 10 min" style duration, rounded down to the minute.
    static func durationText(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: max(interval, 60)) ?? ""
    }
}
