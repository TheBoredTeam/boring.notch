//
//  BoringCalendar.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import SwiftUI
import Defaults

struct Config: Equatable {
//    var count: Int = 10  // 3 days past + today + 7 days future
    var past: Int = 7
    var future: Int = 14
    var steps: Int = 1  // Each step is one day
    var spacing: CGFloat = 0
    var showsText: Bool = true
    var offset: Int = 2 // Number of dates to the left of the selected date
}

struct WheelPicker: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    @State private var haptics: Bool = false
    @State private var byClick: Bool = false
    let config: Config

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: config.spacing) {
                let totalSteps = config.steps * (config.past + config.future)
                let spacerNum = config.offset
                ForEach(0..<totalSteps + 2 * spacerNum + 1, id: \.self) { index in
                    if(index < spacerNum || index > totalSteps + spacerNum - 1){
                        Spacer().frame(width: 24, height: 24).id(index)
                    } else {
                        let offset = -config.offset - config.past
                        let date = dateForIndex(index, offset: offset)
                        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        dateButton(date: date, isSelected: isSelected, offset: offset){
                            selectedDate = date
                            byClick = true
                            withAnimation{
                                scrollPosition = indexForDate(date, offset: offset) - config.offset
                            }
                            if (Defaults[.enableHaptics]) {
                                haptics.toggle()
                            }
                        }
                    }
                }
            }
            .frame(height: 50)
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollPosition, anchor: .leading)
        .scrollTargetBehavior(.viewAligned)   // Ensures scroll view snaps to button center
        .safeAreaPadding(.horizontal)
        .sensoryFeedback(.alignment, trigger: haptics)
        .onChange(of: scrollPosition) { oldValue, newValue in
            if(!byClick){
                handleScrollChange(newValue: newValue, config: config)
            }else{
                byClick = false
            }
        }
        .onAppear {
            scrollToToday(config: config)
        }
    }

    private func dateButton(date: Date, isSelected: Bool, offset: Int, onClick:@escaping()->Void) -> some View {
        Button(action: onClick) {
            VStack(spacing: 8) {
                dayText(date: dateToString(for: date), isSelected: isSelected)
                dateCircle(date: date, isSelected: isSelected)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            .cornerRadius(8)}
        .buttonStyle(PlainButtonStyle())
        .id(indexForDate(date, offset: offset))
    }

    private func dayText(date: String, isSelected: Bool) -> some View {
        Text(date)
            .font(.caption)
            .foregroundStyle(isSelected ? .primary : .secondary)
    }

    private func dateCircle(date: Date, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : .clear)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0)
                )
            Text("\(date.date)")
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }

    func handleScrollChange(newValue: Int?, config: Config) {
        let offset = -config.offset - config.past
        let todayIndex = indexForDate(Date(), offset: offset)
        guard let newIndex = newValue else { return }
        let targetDateIndex = newIndex + config.offset
        switch targetDateIndex {
        case todayIndex - config.past ..< todayIndex + config.future:
            selectedDate = dateForIndex(targetDateIndex, offset: offset)
            if (Defaults[.enableHaptics]) {
                haptics.toggle()
            }
        default:
            return
        }
    }

    private func scrollToToday(config: Config) {
        let today = Date()
        let todayIndex = indexForDate(today, offset: -config.offset - config.past)
        byClick = true
        scrollPosition = todayIndex - config.offset
        selectedDate = today
    }

    private func indexForDate(_ date: Date, offset: Int) -> Int {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date())
        let targetDate = calendar.startOfDay(for: date)
        let daysDifference = calendar.dateComponents([.day], from: startDate, to: targetDate).day ?? 0
        return daysDifference
    }

    private func dateForIndex(_ index: Int, offset: Int) -> Date {
        let startDate = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return Calendar.current.date(byAdding: .day, value: index, to: startDate) ?? Date()
    }

    private func dateToString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}

struct CalendarView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading) {
                    Text(selectedDate.formatted(.dateTime.month(.abbreviated)))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(selectedDate.formatted(.dateTime.year()))
                        .font(.title3)
                        .fontWeight(.light)
                        .foregroundColor(.secondary)
                }
                
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
            .padding(.vertical, 4)


            if calendarManager.events.isEmpty {
                EmptyEventsView()
            } else {
                EventListView(events: calendarManager.events)
            }
        }
        .listRowBackground(Color.clear)
        .onChange(of: selectedDate) {
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        .onChange(of: vm.notchState) { _, _ in
            Task {
                await calendarManager.updateCurrentDate(Date.now)
            }
        }
        .onAppear {
            Task {
                await calendarManager.updateCurrentDate(Date.now)
            }
        }
    }
}

struct EmptyEventsView: View {
    var body: some View {
        Spacer(minLength: 0)
        VStack {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title)
                .foregroundColor(.secondary)
            Text("No events today")
                .font(.subheadline)
                .foregroundStyle(.primary)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        Spacer(minLength: 0)
    }
}

struct EventListView: View {
    @Environment(\.openURL) private var openURL
    let events: [EventModel]

    var body: some View {
        Spacer(minLength: 0)
        List {
            ForEach(events) { event in
                Button(action: {
                    if let url = event.calendarAppURL() {
                        openURL(url)
                    }
                }) {
                    eventRow(event)
                }
                .buttonStyle(PlainButtonStyle())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.never)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        Spacer(minLength: 0)
    }

    private func eventRow(_ event: EventModel) -> some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 4) {
                if event.isAllDay {
                    Text("All-day")
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                } else {
                    Text(event.start, style: .time)
                    Text(event.end, style: .time)
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption)
            .frame(width: 44, alignment: .trailing)

            HStack(alignment: .top, spacing: 4) {
                Rectangle()
                    .fill(Color(event.calendar.color))
                    .frame(width: 3)
                    .cornerRadius(1.5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(2)

                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .opacity(event.eventStatus == .ended ? 0.6 : 1)
    }
}

#Preview {
    CalendarView()
        .frame(width: 215, height: 130)
        .background(.black)
        .environmentObject(BoringViewModel())
}
