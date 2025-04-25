//
//  ReminderManager.swift
//  boringNotch
//
//  Created by Andrew Zhao on 4/24/25.
//


import EventKit
import SwiftUI
import Defaults

// MARK: - ReminderManager

class ReminderManager: ObservableObject {
    @Published var reminders: [EKReminder] = []
    @Published var allReminderLists: [EKCalendar] = []
    private var selectedLists: [EKCalendar] = []
    private let eventStore = EKEventStore()
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined

    init() {
        checkReminderAuthorization()
    }

    func checkReminderAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        DispatchQueue.main.async {
            print("🔔 Reminder authorization status: \(status)")
            self.authorizationStatus = status
        }

        switch status {
        case .fullAccess, .writeOnly:
            self.allReminderLists = eventStore.calendars(for: .reminder)
            updateSelectedLists()
            fetchReminders()
        case .notDetermined:
            requestReminderAccess()
        case .restricted, .denied:
            NSLog("Reminder access denied or restricted")
        @unknown default:
            print("Unknown authorization status")
        }
    }

    func requestReminderAccess() {
        eventStore.requestFullAccessToReminders { [weak self] granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔔 Reminder access error: \(error.localizedDescription)")
                }

                self?.authorizationStatus = granted ? .fullAccess : .denied
                if granted {
                    print("🔔 Reminder access granted")
                    self?.fetchReminders()
                } else {
                    print("🔔 Reminder access denied")
                }
            }
        }
    }

    func updateSelectedLists() {
        selectedLists = allReminderLists.filter { getListSelected($0) }
    }

    func getListSelected(_ list: EKCalendar) -> Bool {
        switch Defaults[.reminderSelectionState] {
        case .all:
            return true
        case .selected(let identifiers):
            return identifiers.contains(list.calendarIdentifier)
        }
    }

    func setListSelected(_ list: EKCalendar, isSelected: Bool) {
        var selectionState = Defaults[.reminderSelectionState]

        switch selectionState {
        case .all:
            if !isSelected {
                let identifiers = Set(allReminderLists.map { $0.calendarIdentifier }).subtracting([list.calendarIdentifier])
                selectionState = .selected(identifiers)
            }

        case .selected(var identifiers):
            if isSelected {
                identifiers.insert(list.calendarIdentifier)
            } else {
                identifiers.remove(list.calendarIdentifier)
            }

            selectionState = identifiers.count == allReminderLists.count ? .all : .selected(identifiers)
        }

        Defaults[.reminderSelectionState] = selectionState
        fetchReminders()
    }

    func fetchReminders() {
        guard !self.selectedLists.isEmpty else {
            DispatchQueue.main.async {
                self.reminders = []
            }
            return
        }

        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: self.selectedLists)
        eventStore.fetchReminders(matching: predicate) { reminders in
            DispatchQueue.main.async {
                self.reminders = (reminders ?? []).sorted {
                    ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture)
                }
                print("🔔 Fetched \(self.reminders.count) reminders")
            }
        }
    }
    
    func toggleCompletion(for reminder: EKReminder) {
        reminder.isCompleted.toggle()
        reminder.completionDate = reminder.isCompleted ? Date() : nil

        do {
            try eventStore.save(reminder, commit: true)
            
            if reminder.isCompleted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.fetchReminders()
                }
            } else {
                fetchReminders()
            }

        } catch {
            print("❌ Failed to update reminder: \(error.localizedDescription)")
        }
    }
}
