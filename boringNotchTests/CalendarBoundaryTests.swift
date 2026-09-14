import Foundation
import XCTest
@testable import boringNotch

final class CalendarBoundaryTests: XCTestCase {
    func testAllDayReminderUsesLocalDateAcrossTimeZones() throws {
        let components = DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 4, day: 20)
        for zone in ["America/Los_Angeles", "Asia/Tokyo", "Pacific/Kiritimati"] {
            let calendar = try calendar(in: zone)
            let date = try XCTUnwrap(components.reminderDate(in: calendar, fallbackTimeZone: TimeZone(secondsFromGMT: 0)))
            XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour], from: date), DateComponents(year: 2026, month: 4, day: 20, hour: 0))
            XCTAssertTrue(components.isAllDayReminder)
        }
    }

    func testSpringAndAutumnReminderDaysUseCalendarBoundaries() throws {
        let calendar = try calendar(in: "America/Edmonton")
        for (month, day, hours) in [(3, 10, 23), (11, 3, 25)] {
            let components = DateComponents(year: 2024, month: month, day: day)
            let date = try XCTUnwrap(components.reminderDate(in: calendar, fallbackTimeZone: nil))
            let interval = try XCTUnwrap(calendar.dateInterval(of: .day, for: date))
            XCTAssertEqual(date, interval.start)
            XCTAssertEqual(interval.duration, Double(hours * 3600))
            let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: date))
            XCTAssertEqual(tomorrow, interval.end)
        }
    }

    func testTimedReminderKeepsItsExplicitTimeZone() throws {
        let calendar = try calendar(in: "America/Los_Angeles")
        let components = DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 4, day: 20, hour: 0, minute: 30)
        let date = try XCTUnwrap(components.reminderDate(in: calendar, fallbackTimeZone: TimeZone(identifier: "Asia/Tokyo")))
        XCTAssertEqual(calendar.dateComponents([.day, .hour, .minute], from: date), DateComponents(day: 19, hour: 17, minute: 30))
        XCTAssertFalse(components.isAllDayReminder)
    }

    func testTimedReminderUsesFallbackTimeZoneOnlyWhenComponentsHaveNone() throws {
        let calendar = try calendar(in: "America/Los_Angeles")
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let components = DateComponents(year: 2026, month: 4, day: 20, hour: 0, minute: 30)
        let utcDate = try XCTUnwrap(components.reminderDate(in: calendar, fallbackTimeZone: utc))
        let localDate = try XCTUnwrap(components.reminderDate(in: calendar, fallbackTimeZone: nil))
        XCTAssertEqual(localDate.timeIntervalSince(utcDate), 7 * 3600)
    }

    func testAllDayReminderUsesGregorianDateInNonGregorianSystemCalendar() throws {
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Bangkok"))
        let components = DateComponents(year: 2026, month: 4, day: 20)
        let date = try XCTUnwrap(components.reminderDate(in: calendar, fallbackTimeZone: nil))
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        XCTAssertEqual(gregorian.component(.year, from: date), 2026)
        XCTAssertEqual(gregorian.component(.day, from: date), 20)
    }

    func testWeekStartUsesSystemOrExplicitWeekday() {
        XCTAssertEqual(WeekStartDay.system.firstWeekday, Calendar.current.firstWeekday)
        let expected: [(WeekStartDay, Int)] = [(.sunday, 1), (.monday, 2), (.tuesday, 3), (.wednesday, 4), (.thursday, 5), (.friday, 6), (.saturday, 7)]
        for (setting, weekday) in expected { XCTAssertEqual(setting.firstWeekday, weekday) }
    }

    private func calendar(in timeZone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZone))
        return calendar
    }
}
