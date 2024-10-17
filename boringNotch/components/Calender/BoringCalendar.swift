//
//  BoringCalender.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import EventKit
import SwiftUI

struct Config: Equatable {
    var count: Int = 10  // 3 days past + today + 7 days future
    var steps: Int = 1  // Each step is one day
    var spacing: CGFloat = 1
    var showsText: Bool = true
}

struct WheelPicker: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    @State private var haptics: Bool = false
    let config: Config
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: config.spacing) {
                let totalSteps = config.steps * config.count
                ForEach(0..<totalSteps, id: \.self) { index in
                    dateButton(for: index)
                }
            }
            .frame(height: 50)
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrollPosition)
        .safeAreaPadding(.horizontal)
        .sensoryFeedback(.alignment, trigger: haptics)
        .onChange(of: scrollPosition) { oldValue, newValue in
            if let newIndex = newValue {
                selectedDate = dateForIndex(newIndex)
                haptics.toggle()
            }
        }
        .onAppear {
            scrollToToday()
        }
    }
    
    private func dateButton(for index: Int) -> some View {
        Button(action: {
            selectedDate = dateForIndex(index)
            scrollPosition = index
            haptics.toggle()
        }) {
            VStack(spacing: 2) {
                dayText(for: index)
                dateCircle(for: index)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .id(index)
    }
    
    private func dayText(for index: Int) -> some View {
        Text(dayForIndex(index))
            .font(.caption2)
            .foregroundStyle(isDateSelected(index) ? Color.accentColor : .gray)
    }
    
    private func dateCircle(for index: Int) -> some View {
        ZStack {
            Circle()
                .fill(isDateSelected(index) ? Color.accentColor : .clear)
                .frame(width: 24, height: 24)
            Text("\(dateForIndex(index).date)")
                .font(.title3)
                .foregroundStyle(isDateSelected(index) ? .white : .gray)
        }
    }
    
    private func scrollToToday() {
        let today = Date()
        let todayIndex = indexForDate(today)
        scrollPosition = todayIndex
        selectedDate = today
    }
    
    private func indexForDate(_ date: Date) -> Int {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -3, to: Date()) ?? Date())
        let targetDate = calendar.startOfDay(for: date)
        let daysDifference = calendar.dateComponents([.day], from: startDate, to: targetDate).day ?? 0
        return daysDifference
    }

    private func dateForIndex(_ index: Int) -> Date {
        let startDate = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        return Calendar.current.date(byAdding: .day, value: index, to: startDate) ?? Date()
    }

    private func dayForIndex(_ index: Int) -> String {
        let date = dateForIndex(index)
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func isDateSelected(_ index: Int) -> Bool {
        Calendar.current.isDate(dateForIndex(index), inSameDayAs: selectedDate)
    }
}

struct CalendarView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject private var calendarManager = CalendarManager()
    @State private var selectedDate = Date()

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(selectedDate, format: .dateTime.month())")
                    .font(.system(size: 18))
                    .fontWeight(.semibold)
                ZStack {
                    WheelPicker(selectedDate: $selectedDate, config: Config())
                    HStack {
                        LinearGradient(
                            colors: [.black, .clear], startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 20)
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black], startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 20)
                    }
                }
            }
            if calendarManager.events.isEmpty {
                EmptyEventsView()
            } else {
                EventListView(events: calendarManager.events)
            }
        }
        .listRowBackground(Color.clear)
        .onChange(of: selectedDate) { _, newDate in
            calendarManager.updateCurrentDate(newDate)
        }
        .onChange(of: vm.notchState) { _, _ in
            calendarManager.updateCurrentDate(Date.now)
        }
        .onAppear {
            calendarManager.updateCurrentDate(Date.now)
        }
    }
}

struct EmptyEventsView: View {
    var body: some View {
        ScrollView {
            Text("No events today")
                .font(.headline)
            Text("Enjoy your free time!")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
}

struct EventListView: View {
    let events: [EKEvent]

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                ForEach(events.indices, id: \.self) { index in
                    HStack(alignment: .top) {
                        VStack(alignment: .trailing) {
                            if isAllDayEvent(
                                start: events[index].startDate, end: events[index].endDate)
                            {
                                Text("All-day")
                            } else {
                                Text("\(events[index].startDate, style: .time)")
                                Text("\(events[index].endDate, style: .time)")
                            }
                        }
                        .multilineTextAlignment(.trailing)
                        .padding(.bottom, 8)
                        .font(.caption2)

                        VStack(spacing: 5) {
                            Image(
                                systemName: isEventEnded(events[index].endDate)
                                    ? "checkmark.circle" : "circle"
                            )
                            .foregroundColor(isEventEnded(events[index].endDate) ? .green : .gray)
                            .font(.footnote)
                            Rectangle()
                                .frame(width: 1)
                                .foregroundStyle(.gray.opacity(0.5))
                                .opacity(index == events.count - 1 ? 0 : 1)
                        }
                        .padding(.top, 1)

                        Text(events[index].title)
                            .font(.footnote)
                            .foregroundStyle(.gray)

                        Spacer(minLength: 0)
                    }
                    .opacity(isEventEnded(events[index].endDate) ? 0.6 : 1)
                }
            }
        }
        .scrollTargetBehavior(.viewAligned)
    }

    private func isAllDayEvent(start: Date, end: Date) -> Bool {
        let calendar = Calendar.current

        guard calendar.isDate(start, inSameDayAs: end) else {
            return false
        }

        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)

        return startComponents.hour == 0 && startComponents.minute == 0 && endComponents.hour == 23
            && endComponents.minute == 59
    }

    private func isEventEnded(_ end: Date) -> Bool {
        return Date.now > end
    }
}

// Keep the CalendarManager, EmptyEventsView, and EventListView as they were in the previous implementation

#Preview {
    CalendarView()
        .frame(width: 250)
        .padding(.horizontal)
        .background(.black)
        .environmentObject(BoringViewModel())
}
