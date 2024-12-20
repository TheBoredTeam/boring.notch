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
        self.currentWeekStartDate = CalendarManager.startOfWeek(Date())
        checkCalendarAuthorization()
    }
    
    func checkCalendarAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
        
        switch status {
            case .authorized:
                self.allCalendars = eventStore.calendars(for: .event)
                updateSelectedCalendars()
                fetchEvents()
            case .notDetermined:
                requestCalendarAccess()
            case .restricted, .denied:
                // Handle the case where the user has denied or restricted access
                NSLog("Calendar access denied or restricted")
            case .fullAccess:
                NSLog("Full access")
            case .writeOnly:
                NSLog("Write only")
            @unknown default:
                print("Unknown authorization status")
        }
    }
    
    func requestCalendarAccess() {
        eventStore.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                self.authorizationStatus = granted ? .fullAccess : .denied
            }
            
            if granted {
                self.fetchEvents()
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
        }
    }
    
    func moveToNextWeek() {
        if let nextWeek = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: currentWeekStartDate) {
            currentWeekStartDate = nextWeek
            fetchEvents()
        }
    }
    
    func moveToPreviousWeek() {
        if let previousWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentWeekStartDate) {
            currentWeekStartDate = previousWeek
            fetchEvents()
        }
    }
    
    static func startOfWeek(_ date: Date) -> Date {
        let firstWeekday = Calendar.current.firstWeekday - 1
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        return Calendar.current.date(byAdding: .day, value: firstWeekday,to: start)!
    }
    
    func updateCurrentDate(_ date: Date) {
        currentWeekStartDate = Calendar.current.startOfDay(for: date)
        fetchEvents()
    }
}
