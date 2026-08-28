//
//  LockScreenAgendaWidgetManager.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

@MainActor
final class LockScreenAgendaWidgetManager: ObservableObject {
    static let shared = LockScreenAgendaWidgetManager()

    @Published private(set) var nextCalendarEvent: EventModel?
    @Published private(set) var nextReminder: EventModel?

    private let panel = LockScreenWidgetPanel(allowsInteraction: false)
    private let calendarService = CalendarService()
    private var refreshTimer: Timer?
    private var isLocked = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        Defaults.publisher(.showOnLockScreen)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        Defaults.publisher(.enableLockScreenReminderWidget)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        Defaults.publisher(.enableLockScreenWeatherWidget)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        Defaults.publisher(.lockScreenShowCalendarEvent)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        Defaults.publisher(.lockScreenCalendarEventLookaheadHours)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        Defaults.publisher(.lockScreenReminderWidgetHorizontalAlignment)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        Defaults.publisher(.lockScreenReminderWidgetVerticalOffset)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func screenDidLock() {
        isLocked = true
        startRefreshTimer()
        refresh()
    }

    func screenDidUnlock() {
        isLocked = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        panel.hide()
    }

    func refresh() {
        guard isLocked, Defaults[.showOnLockScreen] else {
            panel.hide()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let now = Date()
            let end = now.addingTimeInterval(max(1, Defaults[.lockScreenCalendarEventLookaheadHours]) * 3600)
            let events = await calendarService.events(from: now, to: end, calendars: [])
            guard !Task.isCancelled else { return }
            update(with: events, now: now)
        }
    }

    private func update(with events: [EventModel], now: Date) {
        let upcoming = events.filter { event in
            event.end >= now && !event.type.isReminder
        }
        nextCalendarEvent = upcoming.first

        nextReminder = events.first { event in
            if case .reminder(let completed) = event.type {
                return !completed
            }
            return false
        }

        updateReminderPanel()
    }

    private func updateReminderPanel() {
        guard Defaults[.enableLockScreenReminderWidget],
              let reminder = nextReminder,
              let context = LockScreenDisplayContextProvider.shared.snapshot()
        else {
            panel.hide()
            return
        }

        let size = CGSize(width: 360, height: 48)
        let frame = LockScreenWidgetLayout.reminder(
            in: context.frame,
            size: size,
            alignment: Defaults[.lockScreenReminderWidgetHorizontalAlignment],
            offset: CGFloat(Defaults[.lockScreenReminderWidgetVerticalOffset])
        )
        panel.show(LockScreenReminderWidgetView(reminder: reminder), frame: frame, cornerRadius: 22)
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }
}

private struct LockScreenReminderWidgetView: View {
    let reminder: EventModel

    var body: some View {
        LockScreenWidgetCard(cornerRadius: 22) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(nsColor: reminder.calendar.color))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: reminder.calendar.color))
                    .frame(width: 5, height: 19)

                Text(reminder.title.isEmpty
                    ? LockScreenText.value("Reminder")
                    : reminder.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(reminder.start, style: .time)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(width: 360, height: 48)
        }
    }
}
