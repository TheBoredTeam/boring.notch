//
//  CalendarManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import EventKit
import SwiftUI
import Defaults

// MARK: - CalendarManager

@MainActor
class CalendarManager: ObservableObject {
    @Published var currentWeekStartDate: Date
    @Published var events: [EventModel] = []
    @Published var allCalendars: [CalendarModel] = []
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    private var selectedCalendars: [CalendarModel] = []
    private let calendarService = CalendarService()

    init() {
        self.currentWeekStartDate = CalendarManager.startOfDay(Date())
    }

    func checkCalendarAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        DispatchQueue.main.async {
            print("📅 Current calendar authorization status: \(status)")
            self.authorizationStatus = status
        }

        switch status {
            case .notDetermined:
                self.authorizationStatus = await calendarService.requestAccess() ? .fullAccess : .denied
            case .restricted, .denied:
                // Handle the case where the user has denied or restricted access
                NSLog("Calendar access denied or restricted")
            case .fullAccess:
                NSLog("Full access")
                allCalendars = await calendarService.calendars()
                updateSelectedCalendars()
                events = await calendarService.events(from: currentWeekStartDate, to: Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate)!, calendars: selectedCalendars.map{$0.id})
            case .writeOnly:
                NSLog("Write only")
            @unknown default:
                print("Unknown authorization status")
        }
    }
    
    func updateSelectedCalendars() {
        selectedCalendars = allCalendars.filter { getCalendarSelected($0) }
    }
    
    func getCalendarSelected(_ calendar: CalendarModel) -> Bool {
        switch Defaults[.calendarSelectionState] {
        case .all:
            return true
        case .selected(let identifiers):
            return identifiers.contains(calendar.id)
        }
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
            
            selectionState = identifiers.isEmpty ? .all : identifiers.count == allCalendars.count ? .all : .selected(identifiers) // if empty, select all
        }

        Defaults[.calendarSelectionState] = selectionState
        updateSelectedCalendars()
        events = await calendarService.events(from: currentWeekStartDate, to: Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate)!, calendars: selectedCalendars.map{$0.id})
    }
    
    static func startOfDay(_ date: Date) -> Date {
        return Calendar.current.startOfDay(for: date)
    }
    
    func updateCurrentDate(_ date: Date) async {
        currentWeekStartDate = Calendar.current.startOfDay(for: date)
        events = await calendarService.events(from: currentWeekStartDate, to: Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate)!, calendars: selectedCalendars.map{$0.id})
    }
}
