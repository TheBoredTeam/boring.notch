//
//  CalendarYearGridView.swift
//  boringNotch
//

import SwiftUI

/// Compact 3×4 month-name picker for the home-notch calendar column.
struct CalendarYearGridView: View {
    let year: Date
    var onSelectMonth: (Date) -> Void

    private let calendar = Calendar.current

    private var months: [Date] {
        guard let yearInterval = calendar.dateInterval(of: .year, for: year) else { return [] }
        return (0..<12).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: yearInterval.start)
        }
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3),
            spacing: 2
        ) {
            ForEach(months, id: \.self) { month in
                monthButton(month)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .buttonStyle(.plain)
    }

    private func monthButton(_ month: Date) -> some View {
        let isCurrentMonth = calendar.isDate(month, equalTo: Date(), toGranularity: .month)

        return Button {
            onSelectMonth(month)
        } label: {
            Text(month.formatted(.dateTime.month(.abbreviated)))
                .font(.system(size: 12, weight: isCurrentMonth ? .semibold : .medium))
                .foregroundStyle(isCurrentMonth ? Color.effectiveAccent : Color(white: 0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
    }
}
