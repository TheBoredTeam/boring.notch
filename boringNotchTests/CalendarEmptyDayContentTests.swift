import AppKit
import Foundation
import XCTest
@testable import boringNotch

final class CalendarEmptyDayContentTests: XCTestCase {
    // MARK: Day progress

    func testDayProgressForTodayReportsElapsedFraction() throws {
        let calendar = try gregorian(in: "Europe/Berlin")
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12)))
        let progress = DayProgress(for: noon, now: noon, calendar: calendar)
        XCTAssertEqual(progress.dayOfYear, 313)
        XCTAssertEqual(progress.daysInYear, 365)
        XCTAssertEqual(try XCTUnwrap(progress.fractionOfDayElapsed), 0.5, accuracy: 0.0001)
    }

    func testDayProgressForAnotherDayHasNoFraction() throws {
        let calendar = try gregorian(in: "Europe/Berlin")
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2028, month: 3, day: 1, hour: 9)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let progress = DayProgress(for: tomorrow, now: now, calendar: calendar)
        XCTAssertNil(progress.fractionOfDayElapsed)
        XCTAssertEqual(progress.daysInYear, 366, "2028 is a leap year")
        XCTAssertEqual(progress.dayOfYear, 62)
    }

    // MARK: World clock

    func testWorldClockOffsetAheadAndBehind() throws {
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let kolkata = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        // 2026-11-09 is outside European summer time: Berlin is UTC+1.
        let date = Date(timeIntervalSince1970: 1_794_211_200)
        XCTAssertEqual(WorldClock.offset(of: tokyo, from: berlin, at: date), 8 * 3600)
        XCTAssertEqual(WorldClock.offset(of: berlin, from: tokyo, at: date), -8 * 3600)
        XCTAssertEqual(WorldClock.offset(of: kolkata, from: berlin, at: date), 4 * 3600 + 30 * 60)
        XCTAssertEqual(WorldClock.offset(of: berlin, from: berlin, at: date), 0)
    }

    // MARK: Next event

    func testNextEventSkipsEndedCompletedAndHiddenAllDayEvents() throws {
        let now = Date(timeIntervalSince1970: 1_794_211_200)
        let ended = event("ended", start: now - 7200, end: now - 3600)
        let doneReminder = event("done", start: now + 600, end: now + 600, type: .reminder(completed: true))
        let allDay = event("all-day", start: now + 1800, end: now + 86_400, isAllDay: true)
        let later = event("later", start: now + 3 * 86_400, end: now + 3 * 86_400 + 3600)
        let soon = event("soon", start: now + 3600, end: now + 7200)
        let events = [ended, doneReminder, allDay, later, soon]

        XCTAssertEqual(NextEventFinder.firstUpcoming(in: events, after: now, hideAllDay: true)?.id, "soon")
        XCTAssertEqual(NextEventFinder.firstUpcoming(in: events, after: now, hideAllDay: false)?.id, "all-day")
        XCTAssertNil(NextEventFinder.firstUpcoming(in: [ended, doneReminder], after: now, hideAllDay: false))
    }

    func testDaysAwayCountsCalendarDays() throws {
        let calendar = try gregorian(in: "Europe/Berlin")
        let lateEvening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 23)))
        let nextMorning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 7)))
        let inThreeDays = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 1)))
        XCTAssertEqual(NextEventFinder.daysAway(lateEvening, from: lateEvening, calendar: calendar), 0)
        XCTAssertEqual(NextEventFinder.daysAway(nextMorning, from: lateEvening, calendar: calendar), 1)
        XCTAssertEqual(NextEventFinder.daysAway(inThreeDays, from: lateEvening, calendar: calendar), 3)
    }

    // MARK: Daylight

    func testDaylightStatus() {
        let sunrise = Date(timeIntervalSince1970: 1_000_000)
        let sunset = sunrise + 10 * 3600
        XCTAssertEqual(DaylightStatus(now: sunrise - 600, sunrise: sunrise, sunset: sunset), .beforeSunrise(600))
        XCTAssertEqual(DaylightStatus(now: sunrise + 3600, sunrise: sunrise, sunset: sunset), .daylightLeft(9 * 3600))
        XCTAssertEqual(DaylightStatus(now: sunset + 1, sunrise: sunrise, sunset: sunset), .afterSunset)
    }

    // MARK: Open-Meteo decoding

    func testForecastDecodesAndMatchesLocalDay() throws {
        // Two days in Asia/Tokyo (UTC+9): 2026-11-09 and 2026-11-10 at local midnight.
        let json = """
        {
          "utc_offset_seconds": 32400,
          "current": { "time": 1794200000, "temperature_2m": 14.6, "weather_code": 2, "is_day": 1 },
          "daily": {
            "time": [1794150000, 1794236400],
            "weather_code": [2, 61],
            "temperature_2m_max": [17.1, null],
            "temperature_2m_min": [9.4, 8.0],
            "sunrise": [1794174000, 1794260460],
            "sunset": [1794211800, 1794298140]
          }
        }
        """
        let forecast = try JSONDecoder().decode(OpenMeteoForecast.self, from: Data(json.utf8))
        XCTAssertEqual(forecast.current?.temperature, 14.6)
        XCTAssertEqual(forecast.current?.weatherCode, 2)

        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let local = try gregorian(in: "Europe/Berlin")
        let nov10 = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 15)))
        let day = try XCTUnwrap(forecast.day(for: nov10, localCalendar: local, placeTimeZone: tokyo))
        XCTAssertEqual(day.weatherCode, 61)
        XCTAssertNil(day.high)
        XCTAssertEqual(day.low, 8.0)
        XCTAssertEqual(day.sunrise, Date(timeIntervalSince1970: 1_794_260_460))

        let nov20 = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 11, day: 20)))
        XCTAssertNil(forecast.day(for: nov20, localCalendar: local, placeTimeZone: tokyo))
    }

    func testGeocodingResultBecomesPlace() throws {
        let json = """
        { "results": [
          { "name": "Paris", "latitude": 48.85, "longitude": 2.35, "country": "France",
            "admin1": "Île-de-France", "timezone": "Europe/Paris" }
        ] }
        """
        let places = try JSONDecoder().decode(GeocodingResponse.self, from: Data(json.utf8)).places
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.displayName, "Paris, Île-de-France, France")
        XCTAssertEqual(places.first?.timeZone?.identifier, "Europe/Paris")
        XCTAssertTrue(try JSONDecoder().decode(GeocodingResponse.self, from: Data("{}".utf8)).places.isEmpty)
    }

    func testDefaultKeepsOriginalMessage() {
        XCTAssertEqual(Defaults.Keys.calendarEmptyDayContent.defaultValue, .noEventsMessage)
    }

    // MARK: Helpers

    private func gregorian(in identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
        return calendar
    }

    private func event(
        _ id: String, start: Date, end: Date, isAllDay: Bool = false, type: EventType = .event(.accepted)
    ) -> EventModel {
        EventModel(
            id: id, start: start, end: end, title: id, location: nil, notes: nil, url: nil,
            isAllDay: isAllDay, type: type,
            calendar: CalendarModel(id: "c", account: "a", title: "C", color: .systemBlue, isSubscribed: false, isReminder: false),
            participants: [], timeZone: nil, hasRecurrenceRules: false, priority: nil, meetingLink: nil
        )
    }
}
