    //
    //  BoringCalender.swift
    //  boringNotch
    //
    //  Created by Harsh Vardhan  Goswami  on 08/09/24.
    //

import EventKit
import SwiftUI

struct Config: Equatable {
    var count: Int = 14 // One week
    var steps: Int = 1 // Each step is one day
    var spacing: CGFloat = 1
    var showsText: Bool = true
}

struct WheelPicker: View {
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int = 0
    let config: Config
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: config.spacing) {
                let totalSteps = config.steps * config.count
                
                ForEach(0 ..< totalSteps, id: \.self) { index in
                    
                    Button(action: {
                        selectedDate = Calendar.current.date(byAdding: .day, value: index - 3, to: Date()) ?? Date()
                    }, label: {
                        VStack {
                            Text(dayForIndex(index))
                                .font(.caption2)
                            ZStack {
                                Circle()
                                    .fill(isDateSelected(index) ? Color.accentColor : .clear)
                                    .frame(width: 24, height: 24)
                                Text("\(dateForIndex(index))")
                                    .font(.title3)
                            }
                        }
                    }).buttonStyle(PlainButtonStyle())
                }
            }
            .frame(height: 50)
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: .init(get: { scrollPosition }, set: { newValue in
            if let newValue {
                scrollPosition = newValue
                selectedDate = Calendar.current.date(byAdding: .day, value: newValue - 3, to: Date()) ?? Date()
            }
        }))
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

struct CalenderView: View {
    @StateObject private var calendarManager = CalendarManager()
    @State private var selectedDate = Date()
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(selectedDate, format: .dateTime.month())")
                    .font(.system(size: 18))
                WheelPicker(selectedDate: $selectedDate, config: Config())
            }
            if calendarManager.events.isEmpty {
                EmptyEventsView()
            } else {
                EventListView(events: calendarManager.events)
            }
        }
        .listRowBackground(Color.clear)
        .padding(.horizontal)
        .onChange(of: selectedDate) { _, newDate in
            calendarManager.updateCurrentDate(newDate)
        }
    }
}

struct EmptyEventsView: View {
    var body: some View {
        VStack {
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
        List(events, id: \.eventIdentifier) { event in
            HStack() {
                Text(event.title)
                    .font(.footnote)
                Text("\(event.startDate, style: .time) - \(event.endDate, style: .time)")
                    .font(.footnote)
            }.listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }.scrollContentBackground(.hidden).listStyle(PlainListStyle())
    }
}

    // Keep the CalendarManager, EmptyEventsView, and EventListView as they were in the previous implementation

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        CalenderView().frame(width: 250)
    }
}
