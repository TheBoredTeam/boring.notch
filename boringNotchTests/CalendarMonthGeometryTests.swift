import Foundation
import XCTest
@testable import boringNotch

final class CalendarMonthGeometryTests: XCTestCase {
    private func calendar(firstWeekday: Int) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    func testAlwaysReturnsSixWeeks() throws {
        let cal = try calendar(firstWeekday: 1)
        for month in 1...12 {
            let cells = CalendarMonthGeometry.cells(containing: try date(2026, month, 15, in: cal), calendar: cal)
            XCTAssertEqual(cells.count, 42, "month \(month)")
        }
    }

    func testSeptember2026SundayFirstStartsOnTuesday() throws {
        let cal = try calendar(firstWeekday: 1)
        let cells = CalendarMonthGeometry.cells(containing: try date(2026, 9, 29, in: cal), calendar: cal)
        XCTAssertEqual(cells.prefix(2).compactMap { $0 }.count, 0)
        XCTAssertEqual(cells[2].map { cal.component(.day, from: $0) }, 1)
        XCTAssertEqual(cells.compactMap { $0 }.count, 30)
    }

    func testMondayFirstShiftsLeadingBlanks() throws {
        let cal = try calendar(firstWeekday: 2)
        let cells = CalendarMonthGeometry.cells(containing: try date(2026, 9, 1, in: cal), calendar: cal)
        XCTAssertEqual(cells.prefix(1).compactMap { $0 }.count, 0)
        XCTAssertEqual(cells[1].map { cal.component(.day, from: $0) }, 1)
    }

    func testLeapFebruaryHas29Days() throws {
        let cal = try calendar(firstWeekday: 1)
        let cells = CalendarMonthGeometry.cells(containing: try date(2028, 2, 10, in: cal), calendar: cal)
        XCTAssertEqual(cells.compactMap { $0 }.count, 29)
    }

    func testMonthStartingOnFirstWeekdayHasNoLeadingBlanks() throws {
        let cal = try calendar(firstWeekday: 1)
        // March 2026 starts on a Sunday.
        let cells = CalendarMonthGeometry.cells(containing: try date(2026, 3, 20, in: cal), calendar: cal)
        XCTAssertEqual(cells[0].map { cal.component(.day, from: $0) }, 1)
        XCTAssertEqual(cells.compactMap { $0 }.count, 31)
    }

    func testCellsAreStartOfDayAndContiguous() throws {
        let cal = try calendar(firstWeekday: 1)
        let days = CalendarMonthGeometry.cells(containing: try date(2026, 10, 5, in: cal), calendar: cal).compactMap { $0 }
        for (index, day) in days.enumerated() {
            XCTAssertEqual(day, cal.startOfDay(for: day))
            XCTAssertEqual(cal.component(.day, from: day), index + 1)
        }
    }
}
