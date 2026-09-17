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
final class CalendarManager: ObservableObject {
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
    private let calendarService: any CalendarServiceProviding
    private var eventsRequestID = 0

    private var eventStoreChangedObserver: NSObjectProtocol?
    /// EventKit can fire EKEventStoreChanged in bursts during syncs; reloads
    /// coalesce so the UI refreshes once per burst instead of per notification.
    private var reloadTask: Task<Void, Never>?

    init(calendarService: any CalendarServiceProviding = CalendarService()) {
        self.calendarService = calendarService
        self.currentWeekStartDate = CalendarManager.startOfDay(Date())
        setupEventStoreChangedObserver()
        Task {
            await reloadCalendarAndReminderLists()
        }
    }

    deinit {
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
            guard let self, self.reloadTask == nil else { return }
            self.reloadTask = Task { @MainActor in
                defer { self.reloadTask = nil }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await self.reloadCalendarAndReminderLists()
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
        DispatchQueue.main.async {
            Log.calendar.debug("📅 Current calendar authorization status: \(String(describing: status))")
            self.calendarAuthorizationStatus = status
        }

        switch status {
        case .notDetermined:
            guard let granted = try? await calendarService.requestAccess(to: .event) else {
                self.calendarAuthorizationStatus = .notDetermined
                return
            }
            self.calendarAuthorizationStatus = granted ? .fullAccess : .denied
            if granted {
                await reloadCalendarAndReminderLists()
                await updateEvents()
            }
        case .restricted, .denied:
            NSLog("Calendar access denied or restricted")
        case .fullAccess:
            NSLog("Full access")
            await reloadCalendarAndReminderLists()
            await updateEvents()
        case .writeOnly:
            NSLog("Write only")
        @unknown default:
            Log.calendar.debug("Unknown authorization status")
        }
    }
    
    func checkReminderAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        DispatchQueue.main.async {
            Log.calendar.debug("📅 Current reminder authorization status: \(String(describing: status))")
            self.reminderAuthorizationStatus = status
        }

        switch status {
        case .notDetermined:
            guard let granted = try? await calendarService.requestAccess(to: .reminder) else {
                self.reminderAuthorizationStatus = .notDetermined
                return
            }
            self.reminderAuthorizationStatus = granted ? .fullAccess : .denied
            if granted {
                await reloadCalendarAndReminderLists()
            }
        case .restricted, .denied:
            NSLog("Reminder access denied or restricted")
        case .fullAccess:
            NSLog("Full access")
            await reloadCalendarAndReminderLists()
        case .writeOnly:
            NSLog("Write only")
        @unknown default:
            Log.calendar.debug("Unknown authorization status")
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
        await setCalendarsSelected([calendar], isSelected: isSelected)
    }

    func setCalendarsSelected(_ calendars: [CalendarModel], isSelected: Bool) async {
        Defaults[.calendarSelectionState] = Defaults[.calendarSelectionState].settingSelected(
            Set(calendars.map(\.id)), isSelected: isSelected, availableIDs: Set(allCalendars.map(\.id)))
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

    /// Query the timeline's rolling range without changing the selected calendar day.
    func events(from start: Date, to end: Date) async -> [EventModel] {
        await reloadCalendarAndReminderLists()
        let identifiers = selectedCalendarIDs
        guard !identifiers.isEmpty else { return [] }
        let result = await calendarService.events(from: start, to: end, calendars: Array(identifiers))
        // EventKit treats an empty per-entity calendar list as every calendar.
        return result.filter { identifiers.contains($0.calendar.id) }
    }

    private func updateEvents() async {
        eventsRequestID += 1
        let requestID = eventsRequestID
        let date = currentWeekStartDate
        let calendarIDs = selectedCalendars.map { $0.id }
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: date) else { return }
        let eventsResult = await calendarService.events(
            from: date,
            to: end,
            calendars: calendarIDs
        )
        guard requestID == eventsRequestID, date == currentWeekStartDate,
              Set(calendarIDs) == Set(selectedCalendars.map(\.id)) else { return }
        self.events = eventsResult
    }
    
    func setReminderCompleted(reminderID: String, completed: Bool) async {
        await calendarService.setReminderCompleted(reminderID: reminderID, completed: completed)
        // Refresh events after updating
        await updateEvents()
    }
}
