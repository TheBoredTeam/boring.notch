//
//  CalendarMonthGeometryTests.swift
//  boringNotch
//

import Foundation

@main
enum CalendarMonthGeometryTests {
    private static var checks = 0
    private static var failures = [String]()

    static func main() {
        let leapFebruary = checkMonth(year: 2024, month: 2, days: 29, firstWeekday: 2)
        expect(leapFebruary.firstIndex(where: { $0 != nil }) == 3,
               "February 2024 starts in Thursday's column when Monday is first")

        let normalFebruary = checkMonth(year: 2025, month: 2, days: 28, firstWeekday: 2)
        expect(normalFebruary.firstIndex(where: { $0 != nil }) == 5,
               "February 2025 starts in Saturday's column when Monday is first")

        let august = checkMonth(year: 2026, month: 8, days: 31, firstWeekday: 2)
        expect(august[35] != nil && august[36] == nil,
               "August 2026 uses a sixth row and ends after Monday 31")

        let sundayFirst = checkMonth(year: 2026, month: 8, days: 31, firstWeekday: 1)
        expect(sundayFirst.firstIndex(where: { $0 != nil }) == 6,
               "August 2026 shifts to Saturday's column when Sunday is first")
        expect(sundayFirst[36] != nil && sundayFirst[37] == nil,
               "Sunday-first August keeps its final day in the sixth row")

        // The year changes; the grid should resist inviting the neighbors over.
        let december = checkMonth(year: 2026, month: 12, days: 31, firstWeekday: 2)
        expect(december[0] == nil && december[32] == nil,
               "December excludes the adjacent November and January days")
        let january = checkMonth(year: 2027, month: 1, days: 31, firstWeekday: 2)
        expect(january[3] == nil && january[35] == nil,
               "January excludes the adjacent December and February days")

        for firstWeekday in 1...7 {
            _ = checkMonth(year: 2026, month: 9, days: 30, firstWeekday: firstWeekday)
        }

        if failures.isEmpty {
            print("PASS: CalendarMonthGeometry (\(checks) checks)")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    @discardableResult
    private static func checkMonth(
        year: Int, month: Int, days: Int, firstWeekday: Int
    ) -> [Date?] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = unwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = firstWeekday
        let date = unwrap(calendar.date(from: DateComponents(year: year, month: month, day: 15)))
        let cells = CalendarMonthGeometry.cells(containing: date, calendar: calendar)
        let dates = cells.compactMap { $0 }
        let label = "\(year)-\(month), first weekday \(firstWeekday)"

        expect(cells.count == 42, "\(label): exactly six complete weeks")
        expect(dates.count == days, "\(label): correct number of days")
        expect(dates.allSatisfy {
            calendar.component(.year, from: $0) == year &&
            calendar.component(.month, from: $0) == month
        }, "\(label): every visible date belongs to the requested month")
        expect(dates.map { calendar.component(.day, from: $0) } == Array(1...days),
               "\(label): each date appears once in chronological order")
        expect(cells.enumerated().allSatisfy { index, date in
            guard let date else { return true }
            return calendar.component(.weekday, from: date) == (index + firstWeekday - 1) % 7 + 1
        }, "\(label): every date aligns with its weekday column")

        return cells
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures.append(message) }
    }
    private static func unwrap<Value>(_ value: Value?, file: StaticString = #file, line: UInt = #line) -> Value {
        guard let value else { preconditionFailure("Missing test fixture", file: file, line: line) }
        return value
    }

}
