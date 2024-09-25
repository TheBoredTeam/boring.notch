//
//  BoringCalender.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import EventKit
import SwiftUI

struct Config: Equatable {
    var count: Int = 14  // One week
    var steps: Int = 1  // Each step is one day
    var spacing: CGFloat = 1
    var showsText: Bool = true
}

struct WheelPicker: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int = 0
    @State private var haptics: Bool = false
    let config: Config

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: config.spacing) {
                let totalSteps = config.steps * config.count

                ForEach(0..<totalSteps, id: \.self) { index in

                    Button(
                        action: {
                            selectedDate =
                                Calendar.current.date(byAdding: .day, value: index - 3, to: Date())
                                ?? Date()
                        },
                        label: {
                            VStack(spacing: 2) {
                                Text(dayForIndex(index))
                                    .font(.caption2)
                                    .foregroundStyle(
                                        isDateSelected(index) ? Color.accentColor : .gray)
                                ZStack {
                                    Circle()
                                        .fill(isDateSelected(index) ? Color.accentColor : .clear)
                                        .frame(width: 24, height: 24)
                                    Text("\(dateForIndex(index))")
                                        .font(.title3)
                                        .foregroundStyle(isDateSelected(index) ? .white : .gray)
                                }
                            }
                        }
                    )
                    .buttonStyle(PlainButtonStyle())
                    .id(dateForIndex(index))
                }
            }
            .frame(height: 50)
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition(
            id: .init(
                get: { scrollPosition },
                set: { newValue in
                    if let newValue {
                        scrollPosition = newValue
                        selectedDate =
                            Calendar.current.date(byAdding: .day, value: newValue - 3, to: Date())
                            ?? Date()
                        vm.enableHaptics ? haptics.toggle() : nil
                    }
                })
        )
        .safeAreaPadding(.horizontal)
        .sensoryFeedback(.alignment, trigger: haptics)
    }

    private func getCurrentDay() -> Int {
        let calendar = Calendar.current
        let today = Date()
        let dayComponent = calendar.component(.day, from: today)
        return dayComponent
    }

    private func dateForIndex(_ index: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: index - 3, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func dayForIndex(_ index: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: index - 3, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func isDateSelected(_ index: Int) -> Bool {
        let date = Calendar.current.date(byAdding: .day, value: index - 3, to: Date()) ?? Date()
        return Calendar.current.isDate(date, inSameDayAs: selectedDate)
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        CalendarView().frame(width: 250)
    }
}
