//
//  BoringCalendar.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import Defaults
import SwiftUI

struct Config: Equatable {
    //    var count: Int = 10  // 3 days past + today + 7 days future
    var past: Int = 7
    var future: Int = 14
    var steps: Int = 1  // Each step is one day
    var spacing: CGFloat = 0
    var showsText: Bool = true
    var offset: Int = 2  // Number of dates to the left/top of the selected date
}

// MARK: - Layout Constants
/// Centralized layout configuration for the WheelPicker to ensure consistent sizing
/// across both horizontal and vertical layouts
enum WheelPickerLayout {
    // MARK: - Shared Constants
    static let dateCircleSize: CGFloat = 20
    static let itemPadding: CGFloat = 4
    static let cornerRadius: CGFloat = 8
    
    // MARK: - Horizontal Layout
    enum Horizontal {
        static let contentHeight: CGFloat = 50
        static let itemSpacing: CGFloat = 8  // VStack spacing between day text and circle
        static let spacerSize: CGFloat = 24
        static let gradientWidth: CGFloat = 20
    }
    
    // MARK: - Vertical Layout
    enum Vertical {
        static let contentWidth: CGFloat = 50
        static let contentHeight: CGFloat = 80  // Fixed height for the vertical scroll area
        static let itemSpacing: CGFloat = 4   // HStack spacing between day text and circle
        static let itemHeight: CGFloat = 32   // Height of each date item (circle + padding)
        static let gradientHeight: CGFloat = 15
        
        /// Calculate spacer height to allow proper centering
        /// This ensures items can scroll to center position
        static func spacerHeight(for containerHeight: CGFloat) -> CGFloat {
            return (containerHeight - itemHeight) / 2
        }
    }
}

struct WheelPicker: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    @State private var haptics: Bool = false
    @State private var byClick: Bool = false
    let config: Config
    @Default(.calendarLayout) var calendarLayout

    var body: some View {
        if calendarLayout == .horizontal {
            horizontalPicker
        } else {
            verticalPicker
        }
    }
    
    // MARK: - Horizontal Picker
    private var horizontalPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: config.spacing) {
                horizontalPickerContent
            }
            .frame(height: WheelPickerLayout.Horizontal.contentHeight)
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .safeAreaPadding(.horizontal)
        .sensoryFeedback(.alignment, trigger: haptics)
        .onChange(of: scrollPosition) { oldValue, newValue in
            if !byClick {
                handleScrollChange(newValue: newValue, config: config)
            } else {
                byClick = false
            }
        }
        .onAppear {
            scrollToToday(config: config)
        }
        .onChange(of: selectedDate) { _, newValue in
            let targetIndex = indexForDate(newValue)
            if scrollPosition != targetIndex {
                byClick = true
                withAnimation {
                    scrollPosition = targetIndex
                }
            }
        }
    }
    
    // MARK: - Vertical Picker
    private var verticalPicker: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: config.spacing) {
                verticalPickerContent
            }
            .frame(width: WheelPickerLayout.Vertical.contentWidth)
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .frame(height: WheelPickerLayout.Vertical.contentHeight)
        .sensoryFeedback(.alignment, trigger: haptics)
        .onChange(of: scrollPosition) { oldValue, newValue in
            if !byClick {
                handleScrollChange(newValue: newValue, config: config)
            } else {
                byClick = false
            }
        }
        .onAppear {
            scrollToToday(config: config)
        }
        .onChange(of: selectedDate) { _, newValue in
            let targetIndex = indexForDate(newValue)
            if scrollPosition != targetIndex {
                byClick = true
                withAnimation {
                    scrollPosition = targetIndex
                }
            }
        }
    }
    
    // MARK: - Horizontal Picker Content
    @ViewBuilder
    private var horizontalPickerContent: some View {
        let spacerNum = config.offset
        let dateCount = totalDateItems()
        let totalItems = dateCount + 2 * spacerNum
        ForEach(0..<totalItems, id: \.self) { index in
            if index < spacerNum || index >= spacerNum + dateCount {
                // Leading/trailing spacers sized to match a date cell
                Spacer()
                    .frame(width: WheelPickerLayout.Horizontal.spacerSize, height: WheelPickerLayout.Horizontal.spacerSize)
                    .id(index)
            } else {
                let date = dateForItemIndex(index: index, spacerNum: spacerNum)
                let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                dateButton(date: date, isSelected: isSelected, id: index) {
                    selectedDate = date
                    byClick = true
                    withAnimation {
                        scrollPosition = index
                    }
                    if Defaults[.enableHaptics] {
                        haptics.toggle()
                    }
                }
            }
        }
    }
    
    // MARK: - Vertical Picker Content
    @ViewBuilder
    private var verticalPickerContent: some View {
        let dateCount = totalDateItems()
        let spacerHeight = WheelPickerLayout.Vertical.spacerHeight(for: WheelPickerLayout.Vertical.contentHeight)
        
        // Top spacer to allow first item to center
        Spacer()
            .frame(width: WheelPickerLayout.Vertical.contentWidth, height: spacerHeight)
            .id(-1)  // Unique ID for top spacer
        
        // Date items
        ForEach(0..<dateCount, id: \.self) { index in
            let date = dateForItemIndex(index: index, spacerNum: 0)
            let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
            dateButton(date: date, isSelected: isSelected, id: index) {
                selectedDate = date
                byClick = true
                withAnimation {
                    scrollPosition = index
                }
                if Defaults[.enableHaptics] {
                    haptics.toggle()
                }
            }
            .frame(height: WheelPickerLayout.Vertical.itemHeight)
        }
        
        // Bottom spacer to allow last item to center
        Spacer()
            .frame(width: WheelPickerLayout.Vertical.contentWidth, height: spacerHeight)
            .id(-2)  // Unique ID for bottom spacer
    }

    private func dateButton(
        date: Date, isSelected: Bool, id: Int, onClick: @escaping () -> Void
    ) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        return Button(action: onClick) {
            Group {
                if calendarLayout == .horizontal {
                    VStack(spacing: WheelPickerLayout.Horizontal.itemSpacing) {
                        dayText(date: dateToString(for: date), isToday: isToday, isSelected: isSelected)
                        dateCircle(date: date, isToday: isToday, isSelected: isSelected)
                    }
                } else {
                    HStack(spacing: WheelPickerLayout.Vertical.itemSpacing) {
                        dayText(date: dateToString(for: date), isToday: isToday, isSelected: isSelected)
                            .fixedSize(horizontal: true, vertical: false)
                        dateCircle(date: date, isToday: isToday, isSelected: isSelected)
                    }
                }
            }
            .padding(.vertical, WheelPickerLayout.itemPadding)
            .padding(.horizontal, WheelPickerLayout.itemPadding)
            .background(isSelected ? Color.effectiveAccentBackground : Color.clear)
            .cornerRadius(WheelPickerLayout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
        .id(id)
    }

    private func dayText(date: String, isToday: Bool, isSelected: Bool) -> some View {
        Text(date)
            .font(.caption)
            .foregroundColor(isSelected ? .white : Color(white: 0.65))
    }

    private func dateCircle(date: Date, isToday: Bool, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isToday ? Color.effectiveAccent : .clear)
                .frame(width: WheelPickerLayout.dateCircleSize, height: WheelPickerLayout.dateCircleSize)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0)
                )
            Text("\(date.date)")
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : Color(white: isToday ? 0.9 : 0.65))
        }
    }

    func handleScrollChange(newValue: Int?, config: Config) {
        guard let newIndex = newValue else { return }
        
        if calendarLayout == .horizontal {
            // Horizontal uses spacer offset
            let spacerNum = config.offset
            let dateCount = totalDateItems()
            guard (spacerNum..<(spacerNum + dateCount)).contains(newIndex) else { return }
            let date = dateForItemIndex(index: newIndex, spacerNum: spacerNum)
            if !Calendar.current.isDate(date, inSameDayAs: selectedDate) {
                selectedDate = date
                if Defaults[.enableHaptics] {
                    haptics.toggle()
                }
            }
        } else {
            // Vertical uses direct 0-based indices (spacers have negative IDs)
            let dateCount = totalDateItems()
            guard (0..<dateCount).contains(newIndex) else { return }
            let date = dateForItemIndex(index: newIndex, spacerNum: 0)
            if !Calendar.current.isDate(date, inSameDayAs: selectedDate) {
                selectedDate = date
                if Defaults[.enableHaptics] {
                    haptics.toggle()
                }
            }
        }
    }

    private func scrollToToday(config: Config) {
        let today = Date()
        byClick = true
        scrollPosition = indexForDate(today)
        selectedDate = today
    }

    // MARK: - Index/Date mapping with steps and spacers
    private func indexForDate(_ date: Date) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDate = cal.startOfDay(for: cal.date(byAdding: .day, value: -config.past, to: today) ?? today)
        let target = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startDate, to: target).day ?? 0
        let stepIndex = max(0, min(days / max(config.steps, 1), totalDateItems() - 1))
        
        if calendarLayout == .horizontal {
            // Horizontal uses spacer offset
            return config.offset + stepIndex
        } else {
            // Vertical uses direct 0-based indices
            return stepIndex
        }
    }

    private func dateForItemIndex(index: Int, spacerNum: Int) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDate = cal.date(byAdding: .day, value: -config.past, to: today) ?? today
        let stepIndex = index - spacerNum
        return cal.date(byAdding: .day, value: stepIndex * max(config.steps, 1), to: startDate) ?? today
    }

    private func totalDateItems() -> Int {
        let range = config.past + config.future
        let step = max(config.steps, 1)
        return Int(ceil(Double(range) / Double(step))) + 1
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
    @Default(.calendarLayout) var calendarLayout

    var body: some View {
        Group {
            if calendarLayout == .horizontal {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 8) {
                        headerView
                        pickerView
                    }

                    eventsView
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        headerView
                        pickerView
                    }
                    .frame(width: WheelPickerLayout.Vertical.contentWidth)

                    eventsView
                }
            }
        }
        .listRowBackground(Color.clear)
        .frame(height: 120)
        .onChange(of: selectedDate) {
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        .onChange(of: vm.notchState) { _, _ in
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
        .onAppear {
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(selectedDate.formatted(.dateTime.month(.abbreviated)))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Text(selectedDate.formatted(.dateTime.year()))
                .font(.title3)
                .fontWeight(.light)
                .foregroundColor(Color(white: 0.65))
        }
    }

    private var pickerView: some View {
        ZStack(alignment: calendarLayout == .horizontal ? .top : .center) {
            WheelPicker(selectedDate: $selectedDate, config: Config())
            if calendarLayout == .horizontal {
                // Horizontal gradient overlays
                HStack(alignment: .top) {
                    LinearGradient(
                        colors: [Color.black, .clear], startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: WheelPickerLayout.Horizontal.gradientWidth)
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color.black], startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: WheelPickerLayout.Horizontal.gradientWidth)
                }
                .frame(height: WheelPickerLayout.Horizontal.contentHeight)
            } else {
                // Vertical gradient overlays
                VStack(alignment: .center, spacing: 0) {
                    LinearGradient(
                        colors: [Color.black, .clear], startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: WheelPickerLayout.Vertical.gradientHeight)
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color.black], startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: WheelPickerLayout.Vertical.gradientHeight)
                }
                .frame(height: WheelPickerLayout.Vertical.contentHeight)
            }
        }
        .frame(
            width: calendarLayout == .vertical ? WheelPickerLayout.Vertical.contentWidth : nil,
            height: calendarLayout == .vertical ? WheelPickerLayout.Vertical.contentHeight : nil
        )
    }

    private var eventsView: some View {
        Group {
            let filteredEvents = EventListView.filteredEvents(
                events: calendarManager.events
            )
            if filteredEvents.isEmpty {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        EmptyEventsView(selectedDate: selectedDate)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                EventListView(events: calendarManager.events)
            }
        }
    }
}

struct EmptyEventsView: View {
    let selectedDate: Date
    
    var body: some View {
        VStack {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title)
                .foregroundColor(Color(white: 0.65))
            Text(Calendar.current.isDateInToday(selectedDate) ? "No events today" : "No events")
                .font(.subheadline)
                .foregroundColor(.white)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
        }
    }
}

struct EventListView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var calendarManager = CalendarManager.shared
    let events: [EventModel]
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    @Default(.showFullEventTitles) private var showFullEventTitles


    static func filteredEvents(events: [EventModel]) -> [EventModel] {
        events.filter { event in
            if event.type.isReminder {
                if case .reminder(let completed) = event.type {
                    return !completed || !Defaults[.hideCompletedReminders]
                }
            }
            // Filter out all-day events if setting is enabled
            if event.isAllDay && Defaults[.hideAllDayEvents] {
                return false
            }
            return true
        }
    }

    private var filteredEvents: [EventModel] {
        Self.filteredEvents(events: events)
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy) {
        let now = Date()
        // Determine a single target using preferred search order:
        // 1) first non-all-day upcoming/in-progress event
        // 2) first all-day event
        // 3) last event (fallback)
        let nonAllDayUpcoming = filteredEvents.first(where: { !$0.isAllDay && $0.end > now })
        let firstAllDay = filteredEvents.first(where: { $0.isAllDay })
        let lastEvent = filteredEvents.last
        guard let target = nonAllDayUpcoming ?? firstAllDay ?? lastEvent else { return }

        Task { @MainActor in
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(filteredEvents) { event in
                    Button(action: {
                        if let url = event.calendarAppURL() {
                            openURL(url)
                        }
                    }) {
                        eventRow(event)
                    }
                    .id(event.id)
                    .padding(.leading, -5)
                    .buttonStyle(PlainButtonStyle())
                    .listRowSeparator(.automatic)
                    .listRowSeparatorTint(.gray.opacity(0.2))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onAppear {
                scrollToRelevantEvent(proxy: proxy)
            }
            .onChange(of: filteredEvents) { _, _ in
                scrollToRelevantEvent(proxy: proxy)
            }
        }
        Spacer(minLength: 0)
    }

    private func eventRow(_ event: EventModel) -> some View {
        if event.type.isReminder {
            let isCompleted: Bool
            if case .reminder(let completed) = event.type {
                isCompleted = completed
            } else {
                isCompleted = false
            }
            return AnyView(
                HStack(spacing: 8) {
                    ReminderToggle(
                        isOn: Binding(
                            get: { isCompleted },
                            set: { newValue in
                                Task {
                                    await calendarManager.setReminderCompleted(
                                        reminderID: event.id, completed: newValue
                                    )
                                }
                            }
                        ),
                        color: Color(event.calendar.color)
                    )
                    .opacity(1.0)  // Ensure the toggle is always fully opaque
                    HStack {
                        Text(event.title)
                            .font(.callout)
                            .foregroundColor(.white)
                            .lineLimit(showFullEventTitles ? nil : 1)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            if event.isAllDay {
                                Text("All-day")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            } else {
                                Text(event.start, style: .time)
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                        }
                        .frame(minWidth: 22, alignment: .trailing)
                    }
                    .opacity(
                        isCompleted
                            ? 0.4
                            : event.start < Date.now && Calendar.current.isDateInToday(event.start)
                                ? 0.6 : 1.0
                    )
                }
                .padding(.vertical, 4)
            )
        } else {
            return AnyView(
                HStack(alignment: .top, spacing: 4) {
                    Rectangle()
                        .fill(Color(event.calendar.color))
                        .frame(width: 3)
                        .cornerRadius(1.5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(showFullEventTitles ? nil : 2)

                        if let location = event.location, !location.isEmpty {
                            Text(location)
                                .font(.caption)
                                .foregroundColor(Color(white: 0.65))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        if event.isAllDay {
                            Text("All-day")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        } else {
                            Text(event.start, style: .time)
                                .foregroundColor(.white)
                            Text(event.end, style: .time)
                                .foregroundColor(Color(white: 0.65))
                        }
                    }
                    .font(.caption)
                    .frame(minWidth: 22, alignment: .trailing)
                }
                .opacity(
                    event.eventStatus == .ended && Calendar.current.isDateInToday(event.start)
                        ? 0.6 : 1.0)
            )
        }
    }
}

struct ReminderToggle: View {
    @Binding var isOn: Bool
    var color: Color

    var body: some View {
        Button(action: {
            isOn.toggle()
        }) {
            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 14, height: 14)
                // Inner fill
                if isOn {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Circle()
                    .fill(Color.black.opacity(0.001))
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(0)
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}

#Preview {
    CalendarView()
        .frame(width: 215, height: 130)
        .background(.black)
        .environmentObject(BoringViewModel())
}