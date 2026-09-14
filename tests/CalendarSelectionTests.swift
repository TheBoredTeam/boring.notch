//
//  CalendarSelectionTests.swift
//  boringNotch
//

import AppKit
import Defaults
import EventKit

private let testSuiteName = "calendar-selection-tests-\(UUID().uuidString)"
private let testSuite: UserDefaults = {
    guard let suite = UserDefaults(suiteName: testSuiteName) else {
        fatalError("Cannot create isolated calendar test preferences")
    }
    return suite
}()

extension Defaults.Keys {
    static let calendarSelectionState = Key<CalendarSelectionState>(
        "calendarSelectionState", default: .all, suite: testSuite)
}

private actor CalendarSelectionService: CalendarServiceProviding {
    var available: [CalendarModel]
    var suspendRequests = false
    var pending: [(Int, [EventModel], CheckedContinuation<[EventModel], Never>)] = []
    var requestID = 0

    init(_ calendars: [CalendarModel]) { available = calendars }
    func requestAccess(to type: EKEntityType) async throws -> Bool { true }
    func calendars() async -> [CalendarModel] { available }
    func setReminderCompleted(reminderID: String, completed: Bool) async {}
    func add(_ calendar: CalendarModel) { available.append(calendar) }
    func suspend() { suspendRequests = true }
    func pendingCount() -> Int { pending.count }

    func events(from start: Date, to end: Date, calendars ids: [String]) async -> [EventModel] {
        requestID += 1
        let number = requestID
        let result = available.filter { ids.contains($0.id) }.map { calendar in
            EventModel(id: calendar.id, start: start, end: end, title: "request-\(number)",
                       location: nil, notes: nil, url: nil, isAllDay: false,
                       type: calendar.isReminder ? .reminder(completed: false) : .event(.accepted),
                       calendar: calendar, participants: [], timeZone: nil,
                       hasRecurrenceRules: false, priority: nil, meetingLink: nil)
        }
        guard suspendRequests else { return result }
        return await withCheckedContinuation { pending.append((number, result, $0)) }
    }

    func complete(at index: Int) {
        let request = pending.remove(at: index)
        request.2.resume(returning: request.1)
    }
}

@main enum CalendarSelectionTests {
    @MainActor static func main() async {
        defer { UserDefaults(suiteName: testSuiteName)?.removePersistentDomain(forName: testSuiteName) }
        let first = calendar("first"), research = calendar("research"), reminder = calendar("reminder", isReminder: true)
        let service = CalendarSelectionService([first, research, reminder])
        let manager = CalendarManager(calendarService: service)
        await manager.reloadCalendarAndReminderLists()
        require(manager.selectedCalendarIDs == [first.id, research.id, reminder.id], "Default selects every calendar and reminder list")

        await manager.setCalendarsSelected(manager.eventCalendars, isSelected: false)
        require(manager.selectedCalendarIDs == [reminder.id], "Deselecting events preserves reminder selection")
        require(manager.events.map(\.calendar.id) == [reminder.id], "Unchecked calendars disappear from legacy events")
        await manager.setCalendarSelected(reminder, isSelected: false)
        require(manager.selectedCalendarIDs.isEmpty && manager.events.isEmpty, "The final unchecked box stays empty")
        let emptyRange = await manager.events(from: Date(), to: Date().addingTimeInterval(86400))
        require(emptyRange.isEmpty, "An empty selection produces no timeline events")
        if case .selected(let ids) = Defaults[.calendarSelectionState] { require(ids.isEmpty, "Empty state is persisted") }
        else { fatalError("Empty selection must not be stored as all") }

        await manager.setCalendarSelected(research, isSelected: true)
        require(manager.selectedCalendarIDs == [research.id], "One checked calendar does not enable other calendars")
        await manager.setCalendarsSelected(manager.reminderLists, isSelected: true)
        require(manager.selectedCalendarIDs == [research.id, reminder.id], "Selecting reminders preserves selected events")
        let selectedRange = await manager.events(from: Date(), to: Date().addingTimeInterval(86400))
        require(Set(selectedRange.map(\.calendar.id)) == [research.id, reminder.id], "Timeline range follows the same selection")

        Defaults[.calendarSelectionState] = .selected(["removed-calendar", first.id])
        manager.updateSelectedCalendars()
        await manager.setCalendarSelected(research, isSelected: true)
        require(!manager.selectedCalendarIDs.contains(reminder.id), "Equal ID counts with stale IDs must not select everything")
        if case .all = Defaults[.calendarSelectionState] { fatalError("Stale IDs must not promote a partial selection") }

        await manager.setCalendarsSelected(manager.allCalendars, isSelected: true)
        if case .all = Defaults[.calendarSelectionState] {} else { fatalError("Selecting every available calendar restores automatic all") }
        let future = calendar("newly-added")
        await service.add(future)
        await manager.reloadCalendarAndReminderLists()
        require(manager.selectedCalendarIDs.contains(future.id), "Automatic all includes newly discovered calendars")
        await manager.setCalendarSelected(future, isSelected: false)
        let secondFuture = calendar("another-new")
        await service.add(secondFuture)
        await manager.reloadCalendarAndReminderLists()
        require(!manager.selectedCalendarIDs.contains(secondFuture.id), "An explicit selection stays explicit when calendars appear")

        await verifyStaleResults(manager: manager, service: service, calendar: research)
        let providerEmpty = await CalendarService().events(from: Date(), to: Date().addingTimeInterval(86400), calendars: [])
        require(providerEmpty.isEmpty, "The provider treats an empty ID array as no calendars")
        print("Calendar selection: all checks passed (checkboxes, bulk selection, stale IDs, discovery, empty queries, out-of-order refreshes).")
    }

    @MainActor private static func verifyStaleResults(manager: CalendarManager, service: CalendarSelectionService, calendar: CalendarModel) async {
        await service.suspend()
        let first = Task { await manager.setCalendarSelected(calendar, isSelected: false) }
        await waitForRequests(1, service: service)
        let middle = Task { await manager.setCalendarSelected(calendar, isSelected: true) }
        await waitForRequests(2, service: service)
        let latest = Task { await manager.setCalendarSelected(calendar, isSelected: false) }
        await waitForRequests(3, service: service)
        await service.complete(at: 2)
        await latest.value
        let expected = manager.events
        await service.complete(at: 1)
        await middle.value
        await service.complete(at: 0)
        await first.value
        require(manager.events == expected, "An older A-B-A selection request cannot replace the newest A result")

        let oldDate = Date(timeIntervalSince1970: 1_800_000_000)
        let newDate = oldDate.addingTimeInterval(86400)
        let old = Task { await manager.updateCurrentDate(oldDate) }
        await waitForRequests(1, service: service)
        let new = Task { await manager.updateCurrentDate(newDate) }
        await waitForRequests(2, service: service)
        await service.complete(at: 1)
        await new.value
        await service.complete(at: 0)
        await old.value
        require(manager.events.allSatisfy { $0.start == Calendar.current.startOfDay(for: newDate) }, "A delayed old-day result cannot replace the current day")
    }

    private static func waitForRequests(_ count: Int, service: CalendarSelectionService) async {
        for _ in 0..<2000 {
            if await service.pendingCount() == count { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fatalError("Timed out waiting for controlled calendar requests")
    }

    private static func calendar(_ id: String, isReminder: Bool = false) -> CalendarModel {
        CalendarModel(id: id, account: "Test account", title: id, color: .blue,
                      isSubscribed: id == "research", isReminder: isReminder)
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }
}
