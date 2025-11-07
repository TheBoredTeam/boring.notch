//
//  LoftCalendar.swift
//  Zenith Loft
//
//  Created by You on 11/05/25.
//  Part of LoftOS — A Dynamic Notch Experience
//
//  Notes:
//  - Clean-room replacement for a compact calendar surface.
//  - No external deps (Defaults/BoringViewModel) — compiles as-is.
//  - You can later wire real Calendar (EventKit) inside LoftCalendarManager.
//

import SwiftUI

// MARK: - Config

struct LoftCalendarConfig: Equatable {
    var past: Int = 7
    var future: Int = 14
    var steps: Int = 1          // each step is one day
    var spacing: CGFloat = 0
    var showsText: Bool = true
    var offset: Int = 2         // number of dates to the left of the selected date
}

// MARK: - Wheel date picker (clean-room)

struct LoftWheelPicker: View {
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    @State private var hapticTick: Bool = false
    @State private var byClick: Bool = false
    let config: LoftCalendarConfig

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: config.spacing) {
                let spacerNum = config.offset
                let dateCount = totalDateItems()
                let totalItems = dateCount + 2 * spacerNum

                ForEach(0..<totalItems, id: \.self) { index in
                    if index < spacerNum || index >= spacerNum + dateCount {
                        Spacer()
                            .frame(width: 24, height: 24)
                            .id(index)
                    } else {
                        let date = dateForItemIndex(index: index, spacerNum: spacerNum)
                        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        dateButton(date: date, isSelected: isSelected, id: index) {
                            selectedDate = date
                            byClick = true
                            withAnimation { scrollPosition = index }
                            // Light “tick” using sensoryFeedback on supported macOS
                            hapticTick.toggle()
                        }
                    }
                }
            }
            .frame(height: 50)
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .safeAreaPadding(.horizontal)
        .sensoryFeedback(.alignment, trigger: hapticTick)
        .onAppear { scrollToToday() }
        .onChange(of: scrollPosition) { _, newValue in
            if !byClick {
                handleScrollChange(newValue: newValue)
            } else {
                byClick = false
            }
        }
        .onChange(of: selectedDate) { _, newValue in
            // If parent changes selectedDate, center on it
            let targetIndex = indexForDate(newValue)
            if scrollPosition != targetIndex {
                byClick = true
                withAnimation { scrollPosition = targetIndex }
            }
        }
    }

    // MARK: UI bits

    private func dateButton(
        date: Date, isSelected: Bool, id: Int, onClick: @escaping () -> Void
    ) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        return Button(action: onClick) {
            VStack(spacing: 8) {
                dayText(date: weekdayText(for: date), isSelected: isSelected)
                dateCircle(date: date, isToday: isToday, isSelected: isSelected)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .id(id)
    }

    private func dayText(date: String, isSelected: Bool) -> some View {
        Text(date)
            .font(.caption)
            .foregroundColor(isSelected ? .white : Color(white: 0.7))
    }

    private func dateCircle(date: Date, isToday: Bool, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isToday ? Color.accentColor : .clear)
                .frame(width: 20, height: 20)
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : Color(white: isToday ? 0.9 : 0.7))
        }
    }

    // MARK: Behavior

    private func handleScrollChange(newValue: Int?) {
        guard let newIndex = newValue else { return }
        let spacerNum = config.offset
        let dateCount = totalDateItems()
        guard (spacerNum..<(spacerNum + dateCount)).contains(newIndex) else { return }
        let date = dateForItemIndex(index: newIndex, spacerNum: spacerNum)
        if !Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            selectedDate = date
            hapticTick.toggle()
        }
    }

    private func scrollToToday() {
        let today = Date()
        byClick = true
        scrollPosition = indexForDate(today)
        selectedDate = today
    }

    // MARK: Index/Date mapping

    private func indexForDate(_ date: Date) -> Int {
        let spacerNum = config.offset
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDate = cal.startOfDay(for: cal.date(byAdding: .day, value: -config.past, to: today) ?? today)
        let target = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startDate, to: target).day ?? 0
        let stepIndex = max(0, min(days / max(config.steps, 1), totalDateItems() - 1))
        return spacerNum + stepIndex
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

    private func weekdayText(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "E"
        return f.string(from: date)
    }
}

// MARK: - Calendar View (list of events/reminders)

struct LoftCalendarView: View {
    @ObservedObject private var calendarManager = LoftCalendarManager.shared
    @State private var selectedDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            // Header with month/year + wheel picker
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading) {
                    Text(selectedDate.formatted(.dateTime.month(.abbreviated)))
                        .font(.title3).fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(selectedDate.formatted(.dateTime.year()))
                        .font(.title3).fontWeight(.light)
                        .foregroundColor(Color(white: 0.7))
                }

                ZStack(alignment: .top) {
                    LoftWheelPicker(selectedDate: $selectedDate, config: LoftCalendarConfig())
                    HStack(alignment: .top) {
                        LinearGradient(colors: [Color.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 20)
                        Spacer()
                        LinearGradient(colors: [.clear, Color.black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 20)
                    }
                }
            }

            let filteredEvents = LoftEventListView.filteredEvents(events: calendarManager.events)
            if filteredEvents.isEmpty {
                LoftEmptyEventsView()
                Spacer(minLength: 0)
            } else {
                LoftEventListView(events: filteredEvents)
            }
        }
        .listRowBackground(Color.clear)
        .frame(height: 120)
        .onChange(of: selectedDate) { _, newValue in
            Task { await calendarManager.updateCurrentDate(newValue) }
        }
        .onAppear {
            Task {
                await calendarManager.updateCurrentDate(Date())
                selectedDate = Date()
            }
        }
    }
}

struct LoftEmptyEventsView: View {
    var body: some View {
        VStack {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title)
                .foregroundColor(Color(white: 0.65))
            Text("No events today")
                .font(.subheadline)
                .foregroundColor(.white)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
        }
    }
}

// MARK: - Event list

struct LoftEventListView: View {
    let events: [LoftEvent]

    static func filteredEvents(events: [LoftEvent]) -> [LoftEvent] {
        events.filter { event in
            if case .reminder(let completed) = event.type {
                // Hide completed reminders by default
                return completed == false
            }
            return true
        }
    }

    var body: some View {
        List {
            ForEach(events) { event in
                Button(action: {
                    if let url = event.calendarAppURL() {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    eventRow(event)
                }
                .padding(.leading, -5)
                .buttonStyle(.plain)
                .listRowSeparator(.automatic)
                .listRowSeparatorTint(.gray.opacity(0.2))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.never)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        Spacer(minLength: 0)
    }

    @ViewBuilder
    private func eventRow(_ event: LoftEvent) -> some View {
        if case .reminder(let completed) = event.type {
            HStack(spacing: 8) {
                LoftReminderToggle(isOn: .constant(completed), color: Color(event.calendar.color))
                    .opacity(1.0) // visually stable
                HStack {
                    Text(event.title)
                        .font(.callout)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(event.start, style: .time)
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                }
                .opacity(completed ? 0.4 :
                            (event.start < Date() && Calendar.current.isDateInToday(event.start) ? 0.6 : 1.0))
            }
            .padding(.vertical, 4)
        } else {
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
                        .lineLimit(2)

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
                        Text(event.start, style: .time).foregroundColor(.white)
                        Text(event.end, style: .time).foregroundColor(Color(white: 0.65))
                    }
                }
                .font(.caption)
                .frame(minWidth: 44, alignment: .trailing)
            }
            .opacity(event.eventStatus == .ended && Calendar.current.isDateInToday(event.start) ? 0.6 : 1.0)
        }
    }
}

// MARK: - Reminder Toggle (visual only for now)

struct LoftReminderToggle: View {
    @Binding var isOn: Bool
    var color: Color

    var body: some View {
        Button(action: { isOn.toggle() }) {
            ZStack {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 14, height: 14)
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
        .buttonStyle(.plain)
        .padding(0)
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}

// MARK: - Minimal in-file models/manager (no EventKit yet)

enum LoftEventType {
    case event
    case reminder(completed: Bool)

    var isReminder: Bool {
        if case .reminder = self { return true }
        return false
    }
}

enum LoftEventStatus { case upcoming, ongoing, ended }

struct LoftCalendarMeta {
    var color: NSColor = .systemBlue
}

struct LoftEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let calendar: LoftCalendarMeta
    let type: LoftEventType

    var eventStatus: LoftEventStatus {
        let now = Date()
        if end < now { return .ended }
        if start > now { return .upcoming }
        return .ongoing
    }

    func calendarAppURL() -> URL? {
        // Try to open Apple Calendar at the event time (best-effort deep link)
        let interval = Int(start.timeIntervalSinceReferenceDate)
        return URL(string: "ical://dtstart=\(interval)")
    }
}

@MainActor
final class LoftCalendarManager: ObservableObject {
    static let shared = LoftCalendarManager()
    @Published private(set) var events: [LoftEvent] = []

    private init() {}

    /// Replace this stub with real EventKit fetching later.
    func updateCurrentDate(_ date: Date) async {
        // For now, create sample events/reminders for the selected day
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let make = { (hour: Int, minutes: Int) -> Date in
            cal.date(byAdding: .minute, value: hour*60 + minutes, to: startOfDay) ?? date
        }

        // Example events
        let demoEvents: [LoftEvent] = [
            LoftEvent(
                id: UUID().uuidString,
                title: "Standup",
                start: make(9, 30),
                end: make(10, 0),
                isAllDay: false,
                location: "Zoom",
                calendar: LoftCalendarMeta(color: .systemBlue),
                type: .event
            ),
            LoftEvent(
                id: UUID().uuidString,
                title: "Design Review",
                start: make(15, 0),
                end: make(16, 0),
                isAllDay: false,
                location: "Room 2",
                calendar: LoftCalendarMeta(color: .systemPurple),
                type: .event
            ),
            LoftEvent(
                id: UUID().uuidString,
                title: "Buy groceries",
                start: make(18, 0),
                end: make(18, 15),
                isAllDay: false,
                location: nil,
                calendar: LoftCalendarMeta(color: .systemGreen),
                type: .reminder(completed: false)
            )
        ]

        // Simulate async work
        try? await Task.sleep(nanoseconds: 120_000_000)
        self.events = demoEvents
    }

    // Later: hook real toggling for Reminders via EventKit/Reminders API
    func setReminderCompleted(reminderID: String, completed: Bool) async {
        // no-op in stub
    }
}

// MARK: - Preview

#Preview {
    LoftCalendarView()
        .frame(width: 215, height: 130)
        .background(.black)
}
