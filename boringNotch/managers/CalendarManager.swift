//
//  CalenderManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import EventKit
import SwiftUI
import Defaults

// MARK: - CalendarManager

class CalendarManager: ObservableObject {
    @Published var currentWeekStartDate: Date
    @Published var events: [EKEvent] = []
    @Published var allCalendars: [EKCalendar] = []
    private var selectedCalendars: [EKCalendar] = []
    private let eventStore = EKEventStore()
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    
    init() {
        self.currentWeekStartDate = CalendarManager.startOfDay(Date())
        if(Defaults[.showCalendar]) {
            checkCalendarAuthorization()
        }
    }
    
    func checkCalendarAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        DispatchQueue.main.async {
            print("📅 Current calendar authorization status: \(status)")
            self.authorizationStatus = status
        }
        
        switch status {
            case .notDetermined:
                requestCalendarAccess()
            case .restricted, .denied:
                // Handle the case where the user has denied or restricted access
                NSLog("Calendar access denied or restricted")
            case .fullAccess:
                NSLog("Full access")
                self.allCalendars = eventStore.calendars(for: .event)
                updateSelectedCalendars()
                fetchEvents()
            case .writeOnly:
                NSLog("Write only")
            @unknown default:
                print("Unknown authorization status")
        }
    }
    
    func requestCalendarAccess() {
        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("📅 Calendar access error: \(error.localizedDescription)")
                }
                
                self?.authorizationStatus = granted ? .fullAccess : .denied
                if granted {
                    print("📅 Calendar access granted")
                    self?.fetchEvents()
                } else {
                    print("📅 Calendar access denied")
                }
            }
        }
    }
    
    func updateSelectedCalendars() {
        selectedCalendars = allCalendars.filter { getCalendarSelected($0) }
    }
    
    func getCalendarSelected(_ calendar: EKCalendar) -> Bool {
        switch Defaults[.calendarSelectionState] {
        case .all:
            return true
        case .selected(let identifiers):
            return identifiers.contains(calendar.calendarIdentifier)
        }
    }

    func setCalendarSelected(_ calendar: EKCalendar, isSelected: Bool) {
        var selectionState = Defaults[.calendarSelectionState]

        switch selectionState {
        case .all:
            if !isSelected {
                let identifiers = Set(allCalendars.map { $0.calendarIdentifier }).subtracting([calendar.calendarIdentifier])
                selectionState = .selected(identifiers)
            }

        case .selected(var identifiers):
            if isSelected {
                identifiers.insert(calendar.calendarIdentifier)
            } else {
                identifiers.remove(calendar.calendarIdentifier)
            }
            
            selectionState = identifiers.count == allCalendars.count ? .all : .selected(identifiers)
        }

        Defaults[.calendarSelectionState] = selectionState
        fetchEvents()
    }
    
    func fetchEvents() {
        guard !self.selectedCalendars.isEmpty else {
            DispatchQueue.main.async {
                self.events = []
            }
            return
        }
        
        let endOfWeek = Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate)!
        let predicate = eventStore.predicateForEvents(withStart: currentWeekStartDate, end: endOfWeek, calendars: self.selectedCalendars)
        let fetchedEvents = eventStore.events(matching: predicate)
        
        DispatchQueue.main.async {
            self.events = fetchedEvents.sorted { $0.startDate < $1.startDate }
            print("📅 Fetched \(self.events.count) calendar events")
        }
    }
    
    static func startOfDay(_ date: Date) -> Date {
        return Calendar.current.startOfDay(for: date)
    }
    
    func updateCurrentDate(_ date: Date) {
        print("📅 Updating current date to: \(date)")
        currentWeekStartDate = Calendar.current.startOfDay(for: date)
        fetchEvents()
    }
}
