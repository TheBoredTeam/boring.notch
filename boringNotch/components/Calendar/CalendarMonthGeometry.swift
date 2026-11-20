//
//  CalendarMonthGeometry.swift
//  boringNotch
//

import Foundation

enum CalendarMonthGeometry {
    /// 42-cell (6×7) month grid with leading blanks for days before the 1st.
    /// Only in-month days are non-nil (no adjacent-month bleed).
    static func cells(containing date: Date, calendar: Calendar = .current) -> [Date?] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let days = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let leading = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        return (0..<42).map { index in
            let day = index - leading
            guard day >= 0, day < days.count else { return nil }
            return calendar.date(byAdding: .day, value: day, to: month.start)
        }
    }
}
