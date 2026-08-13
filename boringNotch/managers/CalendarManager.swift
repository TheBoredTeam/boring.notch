//
//  CalendarManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import Defaults
import EventKit
import SwiftUI

// MARK: - CalendarManager

@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published var currentWeekStartDate: Date
    @Published var events: [EventModel] = []
    @Published var allCalendars: [CalendarModel] = []
    @Published var eventCalendars: [CalendarModel] = []
    @Published var reminderLists: [CalendarModel] = []
    @Published var selectedCalendarIDs: Set<String> = []
    @Published var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var reminderAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    private var selectedCalendars: [CalendarModel] = []
    private let calendarService = CalendarService()

    private var eventStoreChangedObserver: NSObjectProtocol?
    private var eventStoreRefreshTask: Task<Void, Never>?

    private init() {
        self.currentWeekStartDate = CalendarManager.startOfDay(Date())
        setupEventStoreChangedObserver()
        Task {
            await refreshVisibleCalendar(for: Date())
        }
    }

    deinit {
        eventStoreRefreshTask?.cancel()
        if let observer = eventStoreChangedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupEventStoreChangedObserver() {
        eventStoreChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.eventStoreRefreshTask?.cancel()
                self.eventStoreRefreshTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, let self else { return }
                    await self.refreshCalendarData(updateVisibleEvents: true)
                }
            }
        }
    }

    @MainActor
    func reloadCalendarAndReminderLists() async {
        let all = await calendarService.calendars()
        self.eventCalendars = all.filter { !$0.isReminder }
        self.reminderLists = all.filter { $0.isReminder }
        self.allCalendars = all // for legacy compatibility, can be removed if not needed
        updateSelectedCalendars()
    }

    func checkCalendarAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        calendarAuthorizationStatus = status

        switch status {
        case .notDetermined:
            guard let granted = try? await calendarService.requestAccess(to: .event) else {
                self.calendarAuthorizationStatus = .notDetermined
                return
            }
            let refreshedStatus = EKEventStore.authorizationStatus(for: .event)
            calendarAuthorizationStatus = refreshedStatus
            if granted, refreshedStatus == .fullAccess {
                await refreshCalendarData(updateVisibleEvents: true)
            }
        case .restricted, .denied:
            break
        case .fullAccess:
            await refreshCalendarData(updateVisibleEvents: true)
        case .writeOnly:
            break
        @unknown default:
            break
        }
    }
    
    func checkReminderAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        reminderAuthorizationStatus = status

        switch status {
        case .notDetermined:
            guard let granted = try? await calendarService.requestAccess(to: .reminder) else {
                self.reminderAuthorizationStatus = .notDetermined
                return
            }
            let refreshedStatus = EKEventStore.authorizationStatus(for: .reminder)
            reminderAuthorizationStatus = refreshedStatus
            if granted, refreshedStatus == .fullAccess {
                await reloadCalendarAndReminderLists()
            }
        case .restricted, .denied:
            break
        case .fullAccess:
            await reloadCalendarAndReminderLists()
        case .writeOnly:
            break
        @unknown default:
            break
        }
    }
        

    func updateSelectedCalendars() {
        // Populate selectedCalendarIDs based on Defaults calendar selection state
        switch Defaults[.calendarSelectionState] {
        case .all:
            selectedCalendarIDs = Set(allCalendars.map { $0.id })
        case .selected(let identifiers):
            selectedCalendarIDs = identifiers
        }

        // Update the local calendar objects that correspond to the selected ids
        selectedCalendars = allCalendars.filter { selectedCalendarIDs.contains($0.id) }
    }

    func getCalendarSelected(_ calendar: CalendarModel) -> Bool {
        return selectedCalendarIDs.contains(calendar.id)
    }

    func setCalendarSelected(_ calendar: CalendarModel, isSelected: Bool) async {
        var selectionState = Defaults[.calendarSelectionState]

        switch selectionState {
        case .all:
            if !isSelected {
                let identifiers = Set(allCalendars.map { $0.id }).subtracting([calendar.id])
                selectionState = .selected(identifiers)
            }

        case .selected(var identifiers):
            if isSelected {
                identifiers.insert(calendar.id)
            } else {
                identifiers.remove(calendar.id)
            }

            selectionState =
                identifiers.isEmpty
                ? .all : identifiers.count == allCalendars.count ? .all : .selected(identifiers)  // if empty, select all
        }

        Defaults[.calendarSelectionState] = selectionState
        updateSelectedCalendars()
        await updateEvents()
    }

    static func startOfDay(_ date: Date) -> Date {
        return Calendar.current.startOfDay(for: date)
    }

    func updateCurrentDate(_ date: Date) async {
        currentWeekStartDate = Calendar.current.startOfDay(for: date)
        await updateEvents()
    }

    func refreshVisibleCalendar(for date: Date) async {
        currentWeekStartDate = Calendar.current.startOfDay(for: date)
        await refreshCalendarData(updateVisibleEvents: true)
    }

    private func updateEvents() async {
        let calendarIDs = selectedCalendars.map { $0.id }
        let eventsResult = await calendarService.events(
            from: currentWeekStartDate,
            to: Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate)!,
            calendars: calendarIDs
        )
        self.events = eventsResult
    }

    private func refreshCalendarData(updateVisibleEvents: Bool) async {
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        reminderAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        await reloadCalendarAndReminderLists()
        if updateVisibleEvents, calendarAuthorizationStatus == .fullAccess {
            await updateEvents()
        }
    }

    private func includeAgentCalendarAfterWrite() {
        guard let agentCalendar = eventCalendars.first(where: { $0.title == "蛋神" }) else {
            return
        }

        guard case .selected(var identifiers) = Defaults[.calendarSelectionState],
              !identifiers.contains(agentCalendar.id)
        else {
            return
        }

        identifiers.insert(agentCalendar.id)
        Defaults[.calendarSelectionState] = .selected(identifiers)
        updateSelectedCalendars()
    }
    
    func setReminderCompleted(reminderID: String, completed: Bool) async {
        await calendarService.setReminderCompleted(reminderID: reminderID, completed: completed)
        // Refresh events after updating
        events = await calendarService.events(
            from: currentWeekStartDate,
            to: Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate)!,
            calendars: selectedCalendars.map { $0.id })
    }

    func ensureCalendarAccessIfNeeded() async -> Bool {
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

        if calendarAuthorizationStatus == .notDetermined {
            await checkCalendarAuthorization()
        } else if calendarAuthorizationStatus == .fullAccess {
            await refreshCalendarData(updateVisibleEvents: false)
        }

        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        return calendarAuthorizationStatus == .fullAccess
    }

    func aiScheduleContext(daysAhead: Int = 7, limit: Int = 18) async -> String? {
        guard Defaults[.aiCalendarContextEnabled] else { return nil }
        guard await ensureCalendarAccessIfNeeded() else { return nil }

        await reloadCalendarAndReminderLists()
        updateSelectedCalendars()

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: daysAhead, to: start) ?? start
        let fetchedEvents = await calendarService.events(from: start, to: end, calendars: [])
        let readableEventCalendarCount = eventCalendars.count
        let readableReminderListCount = reminderLists.count

        let relevantEvents = fetchedEvents
            .filter { event in
                if event.type.isReminder,
                   case let .reminder(completed) = event.type,
                   completed && Defaults[.hideCompletedReminders]
                {
                    return false
                }
                return true
            }
            .prefix(limit)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let lines = relevantEvents.map { event in
            let timeRange: String
            if event.isAllDay {
                timeRange = "\(formatter.string(from: event.start)) (all day)"
            } else {
                timeRange = "\(formatter.string(from: event.start)) - \(formatter.string(from: event.end))"
            }

            let typeLabel: String
            switch event.type {
            case .birthday:
                typeLabel = "birthday"
            case .reminder:
                typeLabel = "reminder"
            case .event:
                typeLabel = "event"
            }

            return "- [\(typeLabel)] \(timeRange) | \(event.title) | calendar: \(event.calendar.title)"
        }

        if lines.isEmpty {
            return """
            Calendar read succeeded.
            Range: \(formatter.string(from: start)) - \(formatter.string(from: end)).
            Scope: all accessible EventKit calendars (\(readableEventCalendarCount) event calendars, \(readableReminderListCount) reminder lists).
            Result: 0 events or dated reminders found in this range.
            """
        }

        return """
        Calendar events from today through the next \(daysAhead) days:
        Current local time: \(formatter.string(from: Date()))
        Scope: all accessible EventKit calendars (\(readableEventCalendarCount) event calendars, \(readableReminderListCount) reminder lists).
        \(lines.joined(separator: "\n"))
        """
    }

    func createAIPlannedEvents(_ drafts: [CalendarEventDraft]) async throws -> [CreatedCalendarEvent] {
        guard Defaults[.aiCalendarWriteEnabled] else {
            throw CalendarWriteError.accessDenied
        }

        guard await ensureCalendarAccessIfNeeded() else {
            throw CalendarWriteError.accessDenied
        }

        await reloadCalendarAndReminderLists()
        updateSelectedCalendars()

        let preferredEventCalendarIDs = selectedCalendars
            .filter { !$0.isReminder && !$0.isSubscribed }
            .map(\.id)

        let created = try await calendarService.createEvents(drafts, preferredCalendarIDs: preferredEventCalendarIDs)
        await reloadCalendarAndReminderLists()
        includeAgentCalendarAfterWrite()
        await updateEvents()

        let verificationStart = drafts.map(\.start).min()?.addingTimeInterval(-60) ?? Date()
        let verificationEnd = drafts.map(\.end).max()?.addingTimeInterval(60) ?? Date().addingTimeInterval(60)
        let persistedEvents = await calendarService.events(
            from: verificationStart,
            to: verificationEnd,
            calendars: []
        )
        let persistedIDs = Set(persistedEvents.map(\.id))
        guard created.allSatisfy({ $0.calendarTitle == "蛋神" && persistedIDs.contains($0.identifier) }) else {
            throw CalendarWriteError.verificationFailed
        }
        return created
    }

    #if DEBUG
    func runCalendarRuntimeSelfTest() async -> CalendarRuntimeSelfTestResult {
        guard await ensureCalendarAccessIfNeeded() else {
            return .init(
                authorizationStatus: calendarAuthorizationStatus.rawValue,
                readSucceeded: false,
                writeSucceeded: false,
                readAfterWriteSucceeded: false,
                cleanupSucceeded: false,
                message: "Calendar full access is unavailable."
            )
        }

        let token = UUID().uuidString.prefix(8)
        let title = "蛋神日历自检-\(token)"
        let start = Date().addingTimeInterval(5 * 60)
        let end = start.addingTimeInterval(10 * 60)
        let initialContext = await aiScheduleContext(daysAhead: 1, limit: 100)
        var created: [CreatedCalendarEvent] = []

        do {
            created = try await createAIPlannedEvents([
                .init(
                    title: title,
                    start: start,
                    end: end,
                    notes: "蛋神 Debug 日历读写回归；完成后自动清理。",
                    location: nil,
                    alarmOffsetMinutes: nil
                )
            ])

            let contextAfterWrite = await aiScheduleContext(daysAhead: 1, limit: 100)
            let writeSucceeded = created.count == 1 && created[0].calendarTitle == "蛋神"
            let readAfterWriteSucceeded = contextAfterWrite?.contains(title) == true
            let removedCount = try calendarService.removeEventsForRuntimeTest(
                calendarItemIdentifiers: created.map(\.identifier)
            )
            let eventsAfterCleanup = await calendarService.events(
                from: start.addingTimeInterval(-60),
                to: end.addingTimeInterval(60),
                calendars: []
            )
            let cleanupSucceeded = removedCount == created.count
                && !eventsAfterCleanup.contains(where: { $0.title == title })
            await refreshCalendarData(updateVisibleEvents: true)

            return .init(
                authorizationStatus: calendarAuthorizationStatus.rawValue,
                readSucceeded: initialContext != nil,
                writeSucceeded: writeSucceeded,
                readAfterWriteSucceeded: readAfterWriteSucceeded,
                cleanupSucceeded: cleanupSucceeded,
                message: writeSucceeded && readAfterWriteSucceeded && cleanupSucceeded
                    ? "Calendar runtime self-test passed."
                    : "Calendar runtime self-test returned an incomplete result."
            )
        } catch {
            if !created.isEmpty {
                _ = try? calendarService.removeEventsForRuntimeTest(
                    calendarItemIdentifiers: created.map(\.identifier)
                )
            }
            await refreshCalendarData(updateVisibleEvents: true)
            return .init(
                authorizationStatus: calendarAuthorizationStatus.rawValue,
                readSucceeded: initialContext != nil,
                writeSucceeded: !created.isEmpty,
                readAfterWriteSucceeded: false,
                cleanupSucceeded: created.isEmpty,
                message: error.localizedDescription
            )
        }
    }
    #endif
}

#if DEBUG
struct CalendarRuntimeSelfTestResult: Codable {
    let authorizationStatus: Int
    let readSucceeded: Bool
    let writeSucceeded: Bool
    let readAfterWriteSucceeded: Bool
    let cleanupSucceeded: Bool
    let message: String
}
#endif
