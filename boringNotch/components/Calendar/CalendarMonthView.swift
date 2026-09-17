//
//  CalendarMonthView.swift
//  boringNotch
//
//  Calendar timeline and month presentation.
//

import Defaults
import SwiftUI

/// A quiet date overview beside the player; selecting a day opens its timeline.
struct CalendarMonthView: View {
    var showTimeline: (() -> Void)? = nil
    var selectDate: ((Date) -> Void)? = nil
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.weekStartDay) private var weekStartDay
    @State private var displayedMonth = Date()
    private let columnSpacing: CGFloat = 9

    private var cells: [Date?] {
        let cells = CalendarMonthGeometry.cells(containing: displayedMonth, calendar: calendar)
        let rows = ((cells.lastIndex { $0 != nil } ?? 0) / 7) + 1
        return Array(cells.prefix(rows * 7))
    }

    private var daySize: CGFloat { min(19, 96 / CGFloat(max(1, cells.count / 7))) }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartDay.firstWeekday
        return calendar
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 2) {
                header(today: context.date)
                HStack(spacing: columnSpacing) {
                    ForEach(0..<7, id: \.self) { index in
                        let weekday = (calendar.firstWeekday - 1 + index) % 7
                        Text(calendar.veryShortStandaloneWeekdaySymbols[weekday])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.gray)
                            .frame(width: daySize, height: 11)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(daySize), spacing: columnSpacing), count: 7), spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                        if let date {
                            dayButton(date, today: context.date)
                        } else {
                            Color.clear.frame(width: daySize, height: daySize)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .frame(width: 7 * daySize + 6 * columnSpacing, height: 130, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .center)
            .calendarTodayShortcut { showToday() }
            .onChange(of: calendar.startOfDay(for: context.date)) { oldDay, newDay in
                if calendar.isDate(displayedMonth, equalTo: oldDay, toGranularity: .month) {
                    displayedMonth = newDay
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func header(today: Date) -> some View {
        HStack(spacing: 5) {
            Text(displayedMonth.formatted(.dateTime.month(.abbreviated)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text(displayedMonth.formatted(.dateTime.year()))
                .font(.system(size: 10))
                .foregroundStyle(.gray)
            Spacer(minLength: 0)
            if !calendar.isDate(displayedMonth, equalTo: today, toGranularity: .month) {
                Button("Today", action: showToday)
                    .font(.system(size: 9, weight: .medium))
                    .help("Today (T)")
            }
            monthArrow("chevron.left", offset: -1)
            monthArrow("chevron.right", offset: 1)
            if let showTimeline {
                Button(action: showTimeline) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 10))
                        .frame(width: 18, height: 19)
                }
                .accessibilityLabel("Show day timeline")
                .help("Show day timeline")
            }
        }
        .frame(height: 19)
    }

    private func showToday() {
        let today = Date()
        displayedMonth = today
        coordinator.calendarDate = today
    }

    private func monthArrow(_ symbol: String, offset: Int) -> some View {
        Button {
            let start = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
            displayedMonth = calendar.date(byAdding: .month, value: offset, to: start) ?? start
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.gray)
                .frame(width: 16, height: 19)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(offset < 0 ? "Previous month" : "Next month")
    }

    private func dayButton(_ date: Date, today: Date) -> some View {
        let isToday = calendar.isDate(date, inSameDayAs: today)
        return Button {
            coordinator.calendarDate = date
            selectDate?(date)
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: daySize > 16 ? 11 : 10, weight: isToday ? .bold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isToday ? .white : calendar.isDateInWeekend(date) ? Color.gray : Color.white.opacity(0.86))
                .frame(width: daySize, height: daySize)
                .background(isToday ? Color.red : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .help("Show timeline for \(date.formatted(date: .abbreviated, time: .omitted))")
    }
}
