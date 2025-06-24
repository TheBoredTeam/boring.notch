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
    var past: Int = 3
    var future: Int = 7
    var steps: Int = 1  // Each step is one day
    var spacing: CGFloat = 1
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
                        let isSelected = isDateSelected(index, offset: offset)
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
            VStack(spacing: 2) {
                dayText(date: dateToString(for: date), isSelected: isSelected)
                dateCircle(date: date, isSelected: isSelected)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .id(indexForDate(date, offset: offset))
    }
    
    private func dayText(date: String, isSelected: Bool) -> some View {
        Text(date)
            .font(.caption2)
            .foregroundStyle(isSelected ? Color.accentColor : .gray)
    }

    private func dateCircle(date: Date, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : .clear)
                .frame(width: 24, height: 24)
            Text("\(date.date)")
                .font(.title3)
                .foregroundStyle(isSelected ? .white : .gray)
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

    private func isDateSelected(_ index: Int, offset: Int) -> Bool {
        Calendar.current.isDate(dateForIndex(index, offset: offset), inSameDayAs: selectedDate)
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
            Task {
                await calendarManager.updateCurrentDate(newDate)
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
        ScrollView {
            Text("No events today")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Enjoy your free time!")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
}

struct EventListView: View {
    @Environment(\.openURL) private var openURL
    let events: [EventModel]

    var body: some View {
        ScrollView(showsIndicators: false) {
            HStack(alignment: .top) {
                VStack(alignment: .trailing, spacing: 5) {
                    ForEach(events.indices, id: \.self) { index in
                        VStack(alignment: .trailing) {
                            if events[index].isAllDay {
                                Text("All-day")
                            } else {
                                Text("\(events[index].start, style: .time)")
                                Text("\(events[index].end, style: .time)")
                            }
                        }
                        .multilineTextAlignment(.trailing)
                        .padding(.bottom, 8)
                        .font(.caption2)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(events.indices, id: \.self) { index in
                        HStack(alignment: .top) {
                            VStack(spacing: 5) {
                                Image(
                                    systemName: events[index].eventStatus == .ended
                                        ? "checkmark.circle" : "circle"
                                )
                                .foregroundColor(events[index].eventStatus == .ended ? .green : .gray)
                                .font(.footnote)
                                Rectangle()
                                    .frame(width: 1)
                                    .foregroundStyle(.gray.opacity(0.5))
                                    .opacity(index == events.count - 1 ? 0 : 1)
                            }
                            .padding(.top, 1)

                            Button {
                                if let url = events[index].calendarAppURL() {
                                    openURL(url)
                                }
                            } label: {
                                Text(events[index].title)
                                    .font(.footnote)
                                    .foregroundStyle(.gray)
                            }
                            .buttonStyle(.plain)

                            Spacer(minLength: 0)
                        }
                        .opacity((events[index].eventStatus == .ended) ? 0.6 : 1)
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .scrollTargetBehavior(.viewAligned)
    }
}

#Preview {
    CalendarView()
        .frame(width: 250)
        .padding(.horizontal)
        .background(.black)
        .environmentObject(BoringViewModel())
}
