//
//  CalendarMonthGridView.swift
//  boringNotch
//

import SwiftUI

/// Compact month date grid sized for the home-notch calendar column (~215×110).
struct CalendarMonthGridView: View {
    let displayedMonth: Date
    let selectedDate: Date
    let daysWithEvents: Set<Date>
    var onSelectDate: (Date) -> Void

    private let columnSpacing: CGFloat = 4
    private let calendar = Calendar.current

    private var cells: [Date?] {
        let all = CalendarMonthGeometry.cells(containing: displayedMonth, calendar: calendar)
        let lastFilled = all.lastIndex { $0 != nil } ?? 0
        let rows = (lastFilled / 7) + 1
        return Array(all.prefix(rows * 7))
    }

    private var rowCount: CGFloat { CGFloat(max(1, cells.count / 7)) }

    /// Keep cells wide enough for two-digit day numbers (10–31).
    private var daySize: CGFloat {
        min(22, max(18, 96 / rowCount))
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: columnSpacing) {
                ForEach(0..<7, id: \.self) { index in
                    let weekday = (calendar.firstWeekday - 1 + index) % 7
                    Text(calendar.veryShortStandaloneWeekdaySymbols[weekday])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(white: 0.55))
                        .frame(width: daySize, height: 10)
                }
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: daySize), spacing: columnSpacing),
                    count: 7
                ),
                spacing: 2
            ) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayButton(date)
                    } else {
                        Color.clear
                            .frame(height: daySize)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 2)
        .buttonStyle(.plain)
    }

    private func dayButton(_ date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let hasEvents = daysWithEvents.contains(calendar.startOfDay(for: date))
        let day = calendar.component(.day, from: date)

        return Button {
            onSelectDate(date)
        } label: {
            Text("\(day)")
                .font(.system(size: 11, weight: isToday || isSelected ? .semibold : .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected || isToday ? .white : Color(white: 0.78))
                .frame(maxWidth: .infinity)
                .frame(height: daySize)
                .background(
                    Circle()
                        .fill(
                            isSelected
                                ? Color.effectiveAccent
                                : isToday
                                    ? Color.effectiveAccent.opacity(0.55)
                                    : Color.clear
                        )
                        .padding(1)
                )
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(hasEvents ? Color.effectiveAccent : Color.clear)
                        .frame(width: 3, height: 3)
                        .offset(y: -1)
                }
                .contentShape(Rectangle())
        }
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
}
