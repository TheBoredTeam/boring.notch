//
//  CalendarSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import EventKit
import SwiftUI

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent
    @Default(.calendarWeekView) var calendarWeekView
    @Default(.weekStartDay) var weekStartDay

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showCalendar) {
                    Text("Show calendar")
                }
                Defaults.Toggle(key: .calendarWeekView) {
                    Text("Weekly view")
                }
                if calendarWeekView {
                    Picker("Week starts on", selection: $weekStartDay) {
                        ForEach(WeekStartDay.allCases) { day in
                            Text(day.localizedString).tag(day)
                        }
                    }
                }
            } header: {
                Text("General")
            } footer: {
                Text("Choose how the calendar is displayed in the notch.")
            }

            Section {
                Defaults.Toggle(key: .hideCompletedReminders) {
                    Text("Hide completed reminders")
                }
                Defaults.Toggle(key: .hideAllDayEvents) {
                    Text("Hide all-day events")
                }
                Defaults.Toggle(key: .autoScrollToNextEvent) {
                    Text("Auto-scroll to next event")
                }
                Defaults.Toggle(key: .showFullEventTitles) {
                    Text("Always show full event titles")
                }
                Defaults.Toggle(key: .joinMeetingOnEventTap) {
                    Text("Join meeting when tapping an event")
                }
            } header: {
                Text("Events")
            }

            Section(header: Text("Calendars")) {
                if calendarManager.calendarAuthorizationStatus != .fullAccess {
                    PermissionDeniedNotice(
                        message: "Calendar access is denied. Please enable it in System Settings.",
                        buttonTitle: "Open Calendar Settings",
                        privacyPane: .calendars
                    )
                } else {
                    CalendarList(
                        calendars: calendarManager.eventCalendars,
                        calendarManager: calendarManager,
                        isEnabled: showCalendar
                    )
                }
            }
            Section(header: Text("Reminders")) {
                if calendarManager.reminderAuthorizationStatus != .fullAccess {
                    PermissionDeniedNotice(
                        message: "Reminder access is denied. Please enable it in System Settings.",
                        buttonTitle: "Open Reminder Settings",
                        privacyPane: .reminders
                    )
                } else {
                    CalendarList(
                        calendars: calendarManager.reminderLists,
                        calendarManager: calendarManager,
                        isEnabled: showCalendar
                    )
                }
            }
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
        .navigationTitle("Calendar")
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }
}

/// The Privacy & Security panes relevant to calendar data.
private enum PrivacyPane {
    case calendars
    case reminders

    /// System Settings deep link for the pane.
    var settingsURL: URL? {
        switch self {
        case .calendars:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        case .reminders:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
        }
    }
}

/// An access-denied explanation with a shortcut to the relevant pane of
/// System Settings → Privacy & Security.
private struct PermissionDeniedNotice: View {
    let message: String
    let buttonTitle: String
    let privacyPane: PrivacyPane

    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding()
            Button(buttonTitle) {
                if let settingsURL = privacyPane.settingsURL {
                    NSWorkspace.shared.open(settingsURL)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A selectable list of calendars (or reminder lists) with their accent-colored
/// toggles. Shared by the Calendars and Reminders sections.
private struct CalendarList: View {
    let calendars: [CalendarModel]
    @ObservedObject var calendarManager: CalendarManager
    let isEnabled: Bool

    var body: some View {
        List {
            ForEach(calendars, id: \.id) { calendar in
                Toggle(
                    isOn: Binding(
                        get: { calendarManager.getCalendarSelected(calendar) },
                        set: { isSelected in
                            Task {
                                await calendarManager.setCalendarSelected(
                                    calendar, isSelected: isSelected)
                            }
                        }
                    )
                ) {
                    Text(calendar.title)
                }
                .accentColor(lighterColor(from: calendar.color))
                .disabled(!isEnabled)
            }
        }
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    let nr = lighten(r)
    let ng = lighten(g)
    let nb = lighten(b)

    return Color(red: Double(nr), green: Double(ng), blue: Double(nb), opacity: Double(a))
}
