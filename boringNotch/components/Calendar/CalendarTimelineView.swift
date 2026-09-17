//
//  CalendarTimelineView.swift
//  boringNotch
//

import Defaults
import EventKit
import SwiftUI

@MainActor
struct CalendarTimelineView: View {
    @ObservedObject private var manager = CalendarManager.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.calendarPaneTimelineScale) private var timelineScale
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewportWidth = 524.0
    @State private var windowCenter: Date
    @State private var displayedDate: Date
    @State private var targetDay: Date
    @State private var targetTime: Date
    @State private var events: [EventModel] = []
    @State private var selectedEvent: EventModel?
    @State private var reloadID = 0
    @State private var resetID = 0
    @State private var todayResetID: Int?
    @State private var todayFlashID = 0
    @State private var todayHighlighted = false
    @State private var pendingInitialPosition = true
    @State private var loading = true
    @State private var calendarAccess = EKEventStore.authorizationStatus(for: .event)
    @State private var reminderAccess = EKEventStore.authorizationStatus(for: .reminder)

    init() {
        let date = Calendar.current.startOfDay(for: BoringViewCoordinator.shared.calendarDate)
        _windowCenter = State(initialValue: date)
        _displayedDate = State(initialValue: date)
        _targetDay = State(initialValue: date)
        _targetTime = State(initialValue: Self.initialTime(for: date))
    }

    private var fitScale: Double { viewportWidth / ((visibleRanges.map(\.duration).max() ?? 12 * 3600) / 3600) / 96 }
    private var pointsPerHour: Double { CalendarTimelineScale.pointsPerHour(for: timelineScale, fitting: viewportWidth,
                                                                          duration: visibleRanges.map(\.duration).max() ?? 12 * 3600) }
    private var days: [CalendarDayStackGeometry.Day] { CalendarDayStackGeometry.days(centeredOn: windowCenter) }
    private var hasAccess: Bool { calendarAccess == .fullAccess || reminderAccess == .fullAccess }
    private var requestID: String { "\(days.first?.id.timeIntervalSince1970 ?? 0)-\(reloadID)" }
    private var visibleEvents: [EventModel] {
        events.filter {
            if $0.isAllDay && hideAllDayEvents { return false }
            if case .reminder(let completed) = $0.type { return !hideCompletedReminders || !completed }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            if hasAccess {
                ZStack(alignment: .bottom) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let ranges = visibleRanges
                        let width = (ranges.map(\.duration).max() ?? 12 * 3600) / 3600 * pointsPerHour
                        CalendarDayScrollView(days: days, visibleRanges: ranges, targetDay: targetDay, targetTime: targetTime,
                                              focusCurrentTime: todayResetID == resetID, resetID: resetID, pointsPerHour: pointsPerHour,
                                              onScroll: didScroll, onPositionApplied: didPosition) {
                            VStack(spacing: CalendarDayStackGeometry.rowSpacing) {
                                ForEach(days) { day in dayLabel(day, now: context.date) }
                            }
                        } content: {
                            VStack(alignment: .leading, spacing: CalendarDayStackGeometry.rowSpacing) {
                                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                                    CalendarTimelineTrack(day: day.interval, range: ranges[index], events: events(on: day.interval).filter { !$0.isAllDay && !$0.type.isReminder },
                                                          selectedEvent: selectedEvent, now: context.date, width: width, highlighted: todayHighlighted, pointsPerHour: pointsPerHour) {
                                        select($0, on: day.id)
                                    }
                                }
                            }
                            .background(.black)
                        }
                    }
                    if let selectedEvent {
                        CalendarTimelineDetails(event: selectedEvent, showIdentity: selectedBlockIsShort(selectedEvent)) { self.selectedEvent = nil }
                            .frame(height: 100)
                            .background(.black)
                    }
                }
                .frame(height: 204)
                .background {
                    GeometryReader { proxy in
                        Color.clear.onAppear { viewportWidth = max(0, Double(proxy.size.width) - 76) }
                            .onChange(of: proxy.size.width) { _, width in viewportWidth = max(0, Double(width) - 76) }
                    }
                }
                .clipped()
            } else {
                permissionState.frame(height: 204)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 238, alignment: .top)
        .calendarTodayShortcut { goToToday() }
        .task(id: requestID) { await reload() }
        .task(id: todayFlashID) {
            guard todayFlashID > 0 else { return }
            withAnimation(nil) { todayHighlighted = true }
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { todayHighlighted = false }
        }
        .onDisappear { todayHighlighted = false; todayResetID = nil; todayFlashID = 0 }
        .onChange(of: manager.selectedCalendarIDs) { _, _ in reloadID += 1 }
        .onChange(of: coordinator.calendarDate) { _, date in
            if !Calendar.current.isDate(date, inSameDayAs: displayedDate) { jump(to: date) }
        }
        .onChange(of: visibleEvents) { _, events in
            if let selectedEvent, !events.contains(where: { $0.timelineID == selectedEvent.timelineID }) { self.selectedEvent = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in reloadID += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reloadID += 1 }
        .onExitCommand { selectedEvent = nil }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Text(displayedDate.formatted(.dateTime.month(.wide).year())).font(.system(size: 14, weight: .semibold))
            if loading { ProgressView().controlSize(.mini) }
            Spacer(minLength: 8)
            Text("↕ DAYS   ↔ HOURS").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.4))
            CalendarScaleControl(scale: $timelineScale, minimumScale: fitScale)
            dayArrow("chevron.up", offset: -1)
            Button("Today", action: goToToday)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.white.opacity(0.09), in: Capsule()).help("Today (T)")
            dayArrow("chevron.down", offset: 1)
        }
        .buttonStyle(.plain).frame(height: 26)
    }

    private func dayArrow(_ symbol: String, offset: Int) -> some View {
        Button {
            if let date = Calendar.current.date(byAdding: .day, value: offset, to: displayedDate) { jump(to: date) }
        } label: {
            Image(systemName: symbol).font(.system(size: 11)).frame(width: 22, height: 24)
        }
        .help(offset < 0 ? "Previous day" : "Next day")
        .accessibilityLabel(offset < 0 ? "Previous day" : "Next day")
    }

    private func dayLabel(_ day: CalendarDayStackGeometry.Day, now: Date) -> some View {
        let today = Calendar.current.isDate(day.id, inSameDayAs: now)
        let dayEvents = events(on: day.interval)
        return VStack(alignment: .leading, spacing: 4) {
            Text(day.id.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(today ? .red : .white.opacity(0.5))
            Text(day.id.formatted(.dateTime.day()))
                .font(.system(size: 23, weight: .semibold, design: .rounded)).foregroundStyle(today ? .red : .white)
            Text(today ? "TODAY" : day.id.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.35))
            if !dayEvents.isEmpty {
                Menu {
                    ForEach(dayEvents, id: \.timelineID) { event in
                        Button { select(event, on: day.id) } label: {
                            Text("\(event.type.isReminder ? "Reminder" : event.isAllDay ? "All-day" : event.start.formatted(date: .omitted, time: .shortened)): \(event.title)")
                        }
                    }
                } label: {
                    Label("\(dayEvents.count)", systemImage: "rectangle.stack")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("All events and reminders for this day").accessibilityLabel("\(dayEvents.count) events and reminders")
            } else if !loading {
                Text("Free day").font(.system(size: 8)).foregroundStyle(.white.opacity(0.35))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .frame(width: 68, height: CalendarDayStackGeometry.rowHeight, alignment: .topLeading)
        .overlay(alignment: .trailing) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 6, y: 0))
                path.addLine(to: CGPoint(x: 6, y: 8))
                path.move(to: CGPoint(x: 6, y: 82))
                path.addLine(to: CGPoint(x: 6, y: 90))
                path.addLine(to: CGPoint(x: 0, y: 90))
            }
            .stroke(.red.opacity(0.5), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
            .frame(width: 7, height: 90).padding(.trailing, 1)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            if let y = CalendarDayStackGeometry.hiddenTimeOffset(for: now, in: day.interval, visibleRange: visibleRange(for: day.id)) {
                CalendarTimelineTimeBadge(time: now, highlighted: todayHighlighted)
                    .frame(width: 68, height: 16).offset(y: y - 8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var visibleRanges: [DateInterval] {
        CalendarTimelineGeometry.sharedVisibleRanges(in: days.map(\.interval), events: events.map {
            .init(id: $0.timelineID, start: $0.start, end: $0.end, isAllDay: $0.isAllDay, isReminder: $0.type.isReminder)
        })
    }

    private func visibleRange(for date: Date) -> DateInterval {
        let day = CalendarTimelineGeometry.dayInterval(for: date)
        guard let index = days.firstIndex(where: { $0.id == day.start }) else {
            return CalendarTimelineGeometry.visibleRange(in: day, events: [])
        }
        return visibleRanges[index]
    }

    private func events(on day: DateInterval) -> [EventModel] {
        visibleEvents.filter {
            if $0.type.isReminder { return $0.start >= day.start && $0.start < day.end }
            return $0.start < day.end && ($0.end > day.start || ($0.start == $0.end && $0.start >= day.start))
        }
    }

    private func select(_ event: EventModel, on date: Date) {
        todayResetID = nil
        todayHighlighted = false
        selectedEvent = event
        windowCenter = date
        displayedDate = date
        targetDay = date
        coordinator.calendarDate = date
        let day = CalendarTimelineGeometry.dayInterval(for: date)
        if !event.isAllDay && !event.type.isReminder {
            targetTime = max(event.start, day.start).addingTimeInterval(-3600)
        }
        pendingInitialPosition = false
        resetID += 1
    }

    private func selectedBlockIsShort(_ event: EventModel) -> Bool {
        let day = visibleRange(for: targetDay)
        let start = CalendarTimelineGeometry.position(of: event.start, in: day, pointsPerHour: pointsPerHour)
        let end = CalendarTimelineGeometry.position(of: event.end, in: day, pointsPerHour: pointsPerHour)
        return end - start < 52
    }

    private func didScroll(to position: CalendarDayStackGeometry.Position, vertical: Bool) {
        pendingInitialPosition = false
        todayResetID = nil
        todayHighlighted = false
        if vertical { selectedEvent = nil }
        if vertical && !Calendar.current.isDate(displayedDate, inSameDayAs: position.day) {
            displayedDate = position.day
            coordinator.calendarDate = position.day
        }
        if CalendarDayStackGeometry.needsRecentering(position: position, in: days) { windowCenter = position.day }
    }

    private func jump(to date: Date, currentTime: Bool = false) {
        todayResetID = nil
        todayHighlighted = false
        let day = Calendar.current.startOfDay(for: date)
        selectedEvent = nil
        windowCenter = day
        displayedDate = day
        targetDay = day
        coordinator.calendarDate = day
        targetTime = Self.initialTime(for: day, currentTime: currentTime)
        pendingInitialPosition = !currentTime
        resetID += 1
    }

    private func goToToday() {
        jump(to: Date(), currentTime: true)
        todayResetID = resetID
    }

    private func didPosition(_ appliedID: Int) {
        guard appliedID == todayResetID else { return }
        todayFlashID += 1
    }

    private static func initialTime(for date: Date, currentTime: Bool = false) -> Date {
        if currentTime { return Date() }
        if Defaults[.autoScrollToNextEvent] && Calendar.current.isDateInToday(date) {
            return Date().addingTimeInterval(-3600)
        }
        return Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
    }

    private func reload() async {
        calendarAccess = EKEventStore.authorizationStatus(for: .event)
        reminderAccess = EKEventStore.authorizationStatus(for: .reminder)
        guard hasAccess, let span = CalendarDayStackGeometry.span(of: days) else {
            events = []
            selectedEvent = nil
            loading = false
            return
        }
        loading = true
        let result = await manager.events(from: span.start, to: span.end)
        guard !Task.isCancelled, span == CalendarDayStackGeometry.span(of: days) else { return }
        events = result
        if let selectedEvent { self.selectedEvent = result.first { $0.timelineID == selectedEvent.timelineID } }
        if pendingInitialPosition {
            pendingInitialPosition = false
            if Defaults[.autoScrollToNextEvent], !Calendar.current.isDateInToday(displayedDate) {
                let day = CalendarTimelineGeometry.dayInterval(for: displayedDate)
                if let first = events(on: day).first(where: { !$0.isAllDay && !$0.type.isReminder }) {
                    targetTime = max(first.start, day.start).addingTimeInterval(-3600)
                    resetID += 1
                }
            }
        }
        loading = false
    }

    private var permissionState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 24, weight: .light)).foregroundStyle(.white.opacity(0.5))
            Text("Your days, at a glance").font(.system(size: 13, weight: .medium))
            Text("Allow calendar access to see your events here.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            Button(calendarAccess == .notDetermined ? "Connect Calendar" : "Open Calendar Privacy Settings") {
                if calendarAccess == .notDetermined {
                    Task { await manager.checkCalendarAuthorization(); reloadID += 1 }
                } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CalendarTimelineTrack: View {
    let day: DateInterval
    let range: DateInterval
    let events: [EventModel]
    let selectedEvent: EventModel?
    let now: Date
    let width: CGFloat
    let highlighted: Bool
    let pointsPerHour: Double
    let select: (EventModel) -> Void

    private var placements: [CalendarTimelineGeometry.Placement] {
        CalendarTimelineGeometry.layout(events.map { .init(id: $0.timelineID, start: $0.start, end: $0.end) }, in: range, pointsPerHour: pointsPerHour)
    }

    var body: some View {
        let layout = placements
        let counts = CalendarTimelineGeometry.clusterLaneCounts(for: layout)
        let currentDay = now >= range.start && now < range.end
        let progress = CalendarTimelineGeometry.position(of: now, in: range, pointsPerHour: pointsPerHour)
        let badgeWidth = CalendarTimelineTimeBadge.width(for: now)
        VStack(spacing: 2) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.035))
                    .frame(width: range.duration / 3600 * pointsPerHour)
                Rectangle().fill(.white.opacity(0.025)).frame(width: progress).allowsHitTesting(false)
                ForEach(CalendarTimelineGeometry.hourTicks(in: range), id: \.self) { tick in
                    Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
                        .offset(x: CalendarTimelineGeometry.position(of: tick, in: range, pointsPerHour: pointsPerHour)).allowsHitTesting(false)
                }
                ForEach(layout.filter { $0.lane < 2 }) { placement in
                    if let event = events.first(where: { $0.timelineID == placement.id }) {
                        let count = counts[placement.id] ?? 1
                        let laneHeight: CGFloat = count == 1 ? 76 : count == 2 ? 38 : 28
                        eventBlock(event, placement: placement, laneHeight: laneHeight)
                    }
                }
                ForEach(overflowGroups(layout)) { group in
                    Menu {
                        ForEach(group.events, id: \.timelineID) { event in Button(event.title) { select(event) } }
                    } label: {
                        Text("+\(group.events.count) overlapping").font(.system(size: 8, weight: .medium))
                            .lineLimit(1).frame(width: group.width, height: 18, alignment: .leading)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .menuStyle(.borderlessButton).fixedSize().offset(x: group.x, y: 58)
                }
                if currentDay {
                    Rectangle().fill(.red).frame(width: 1.5)
                        .shadow(color: .red.opacity(highlighted ? 0.9 : 0), radius: highlighted ? 6 : 0)
                        .offset(x: progress).allowsHitTesting(false)
                }
            }
            .frame(width: width, height: 76, alignment: .topLeading)
            ZStack(alignment: .topLeading) {
                let badgeLeading = Double(min(max(0, CGFloat(progress) - badgeWidth / 2), max(0, width - badgeWidth)))
                CalendarTimelineHourLabels(range: range, pointsPerHour: pointsPerHour,
                                           exclusions: currentDay ? [badgeLeading..<(badgeLeading + Double(badgeWidth))] : [], format: tickLabel)
                if currentDay {
                    CalendarTimelineTimeBadge(time: now, highlighted: highlighted)
                        .offset(x: min(max(0, CGFloat(progress) - badgeWidth / 2), max(0, width - badgeWidth)))
                }
            }
            .frame(width: width, height: 16, alignment: .topLeading)
        }
        .frame(width: width, height: CalendarDayStackGeometry.rowHeight)
        .overlay(alignment: .topLeading) {
            if let y = CalendarDayStackGeometry.hiddenTimeOffset(for: now, in: day, visibleRange: range) {
                Rectangle().fill(.red.opacity(0.7)).frame(width: width, height: 1)
                    .shadow(color: .red.opacity(highlighted ? 0.8 : 0), radius: highlighted ? 5 : 0)
                    .offset(y: y - 0.5).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    private func eventBlock(_ event: EventModel, placement: CalendarTimelineGeometry.Placement, laneHeight: CGFloat) -> some View {
        let color = Color(event.calendar.color)
        let isSelected = event.timelineID == selectedEvent?.timelineID
        let blockHeight = laneHeight - 4
        return Button { select(event) } label: {
            ZStack(alignment: .leading) {
                Color.clear
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 2)
                    if placement.width >= 52 {
                        VStack(alignment: .leading, spacing: laneHeight >= 52 ? 6 : 1) {
                            Text(event.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(laneHeight >= 52 ? 3 : 1)
                                .truncationMode(.tail)
                            if laneHeight > 30, let location = event.location, !location.isEmpty {
                                Text(location.replacingOccurrences(of: "\n", with: ", "))
                                    .font(.system(size: 9))
                                    .foregroundStyle(color.opacity(0.85))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, laneHeight > 40 ? 4 : 2)
                .padding(.horizontal, placement.width >= 52 ? 4 : 0)
                .frame(width: max(1, placement.width), height: blockHeight, alignment: .leading)
                .background(color.opacity(isSelected ? 0.3 : 0.15), in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isSelected ? color : color.opacity(0.22), lineWidth: 1)
                }
                .clipped()
                .offset(x: placement.x - placement.hitX)
            }
            .frame(width: placement.hitWidth, height: blockHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(event.end < now && Calendar.current.isDateInToday(day.start) ? 0.55 : 1)
        .offset(x: placement.hitX, y: CGFloat(placement.lane) * laneHeight + 2)
        .help("\(event.title)\n\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))\(event.location.map { "\n\($0)" } ?? "")")
        .accessibilityLabel("\(event.title), \(event.start.formatted(date: .omitted, time: .shortened)) to \(event.end.formatted(date: .omitted, time: .shortened)), \(event.location ?? "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func tickLabel(_ tick: Date) -> String {
        let format = Date.FormatStyle.dateTime.hour().minute()
        let label = tick.formatted(format)
        let repeats = CalendarTimelineGeometry.hourTicks(in: range).filter {
            $0 < range.end && $0.formatted(format) == label
        }.count > 1
        return repeats ? "\(label) \(TimeZone.current.abbreviation(for: tick) ?? "")" : label
    }
    private struct OverflowGroup: Identifiable {
        let id: String
        var x: CGFloat
        var width: CGFloat
        var events: [EventModel]
    }

    private func overflowGroups(_ placements: [CalendarTimelineGeometry.Placement]) -> [OverflowGroup] {
        var groups: [OverflowGroup] = []
        for placement in placements.filter({ $0.lane >= 2 }).sorted(by: { $0.hitX < $1.hitX }) {
            guard let event = events.first(where: { $0.timelineID == placement.id }) else { continue }
            if let last = groups.last, last.x + last.width >= placement.hitX {
                groups[groups.count - 1].width = max(last.x + last.width, placement.hitX + placement.hitWidth) - last.x
                groups[groups.count - 1].events.append(event)
            } else {
                groups.append(.init(id: placement.id, x: placement.hitX, width: placement.hitWidth, events: [event]))
            }
        }
        return groups
    }

}

private struct CalendarTimelineTimeBadge: View {
    let time: Date
    let highlighted: Bool

    static func width(for time: Date) -> CGFloat {
        let label = time.formatted(date: .omitted, time: .shortened) as NSString
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        return ceil(label.size(withAttributes: [.font: font]).width) + 10
    }

    var body: some View {
        Text(time.formatted(date: .omitted, time: .shortened))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white).padding(.horizontal, 5)
            .frame(width: Self.width(for: time), height: 16)
            .background(.red, in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(highlighted ? 0.95 : 0), lineWidth: 1.5) }
            .shadow(color: .red.opacity(highlighted ? 0.7 : 0), radius: highlighted ? 6 : 0)
            .accessibilityLabel("Current time \(time.formatted(date: .omitted, time: .shortened))")
    }
}

private struct CalendarTimelineDetails: View {
    @Environment(\.openURL) private var openURL
    let event: EventModel
    let showIdentity: Bool
    let close: () -> Void

    private var duration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(0, event.end.timeIntervalSince(event.start))) ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: close) {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28).background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain).help("Back to days").accessibilityLabel("Back to days")
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    if showIdentity || event.isAllDay || event.type.isReminder {
                        Text(event.title).font(.system(size: 11, weight: .semibold))
                        if let location = event.location, !location.isEmpty {
                            Text(location).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    HStack(spacing: 8) {
                        Circle().fill(Color(event.calendar.color)).frame(width: 5, height: 5)
                        Text(event.calendar.title).lineLimit(1)
                        Text("·").foregroundStyle(.white.opacity(0.3))
                        Text(timeDescription)
                        if !event.isAllDay && !event.type.isReminder {
                            Text("· \(duration)").foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                        Text(notes).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).textSelection(.enabled)
                    }
                    if !event.participants.isEmpty {
                        Label(event.participants.map { $0.name + ($0.isOrganizer ? " (organizer)" : "") }.joined(separator: ", "), systemImage: "person.2")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    }
                    if let url = event.url {
                        Link(destination: url) { Label(url.host ?? "Event link", systemImage: "link").font(.system(size: 10)) }
                    }
                    if let zone = event.timeZone, zone != .current {
                        Text("Event time zone: \(zone.identifier)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                    }
                    Button(event.type.isReminder ? "Open in Reminders ↗" : "Open in Calendar ↗") {
                        if let url = event.calendarAppURL() { openURL(url) }
                    }
                    .font(.system(size: 10, weight: .medium)).buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 6)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var timeDescription: String {
        if event.isAllDay { return "All-day" }
        if event.type.isReminder { return "Due \(event.start.formatted(date: .omitted, time: .shortened))" }
        let sameDay = Calendar.current.isDate(event.start, inSameDayAs: event.end)
        return "\(event.start.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)) – \(event.end.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened))"
    }
}

private extension EventModel {
    var timelineID: String { "\(id)-\(start.timeIntervalSince1970)" }
}
