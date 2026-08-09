import EventKit
import Foundation
import SwiftUI

extension Notification.Name {
    static let dailyWorkflowNeedsPresentation = Notification.Name("DailyWorkflowNeedsPresentation")
    static let dailyWorkflowDidFinish = Notification.Name("DailyWorkflowDidFinish")
}

struct DailyWorkflowSession: Equatable, Identifiable {
    let kind: DailyWorkflowKind
    let date: Date

    var id: String {
        "\(kind.rawValue)-\(date.timeIntervalSinceReferenceDate)"
    }
}

enum DailyPlanningContentState: Equatable {
    case idle
    case loading
    case loaded(DailyReminderSections)
    case permissionDenied
    case failure(String)
}

@MainActor
final class DailyPlanningManager: ObservableObject {
    static let shared = DailyPlanningManager()

    @Published private(set) var preferences: DailyWorkflowPreferences
    @Published private(set) var activeSession: DailyWorkflowSession?
    @Published private(set) var contentState: DailyPlanningContentState = .idle
    @Published private(set) var isFinishingSession = false
    @Published private(set) var updatingReminderIDs: Set<String> = []

    var isPresenting: Bool { activeSession != nil }

    private let store: DailyWorkflowPreferencesStore
    private let calendarService: CalendarServiceProviding
    private var completionState: DailyWorkflowCompletionState
    private var timer: Timer?
    private var evaluationTask: Task<Void, Never>?
    private var eventStoreObserver: NSObjectProtocol?
    private var hasStarted = false

    init(
        store: DailyWorkflowPreferencesStore = DailyWorkflowPreferencesStore(),
        calendarService: CalendarServiceProviding = CalendarService()
    ) {
        self.store = store
        self.calendarService = calendarService
        preferences = store.loadPreferences()
        completionState = store.loadCompletionState()
    }

    deinit {
        timer?.invalidate()
        evaluationTask?.cancel()
        if let eventStoreObserver {
            NotificationCenter.default.removeObserver(eventStoreObserver)
        }
    }

    func start() {
        guard !hasStarted else {
            presentActiveSessionIfNeeded()
            return
        }
        hasStarted = true
        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.activeSession != nil else { return }
                await self?.reloadActiveSession(showLoadingIndicator: false)
            }
        }
        evaluate()
    }

    func presentActiveSessionIfNeeded() {
        guard activeSession != nil else { return }
        NotificationCenter.default.post(name: .dailyWorkflowNeedsPresentation, object: nil)
    }

    func setEnabled(_ isEnabled: Bool, for kind: DailyWorkflowKind) {
        updatePreferences { preferences in
            switch kind {
            case .morningPlanning:
                preferences.morningPlanningEnabled = isEnabled
            case .eveningReview:
                preferences.eveningReviewEnabled = isEnabled
            }
        }
    }

    func setTime(_ date: Date, for kind: DailyWorkflowKind, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        updatePreferences { preferences in
            switch kind {
            case .morningPlanning:
                preferences.morningPlanningMinutes = minutes
            case .eveningReview:
                preferences.eveningReviewMinutes = minutes
            }
        }
    }

    func configuredTime(
        for kind: DailyWorkflowKind, on date: Date = Date(), calendar: Calendar = .current
    ) -> Date {
        DailyWorkflowSchedule.triggerDate(
            for: kind,
            on: date,
            preferences: preferences,
            calendar: calendar
        ) ?? calendar.startOfDay(for: date)
    }

    func beginFinishingActiveSession() {
        guard activeSession != nil, !isFinishingSession else { return }
        isFinishingSession = true
    }

    func finalizeActiveSession() {
        guard let session = activeSession else { return }

        var updatedCompletion = completionState
        updatedCompletion.markCompleted(session.kind, on: session.date, calendar: .current)

        do {
            try store.saveCompletionState(updatedCompletion)
        } catch {
            contentState = .failure("Your completion could not be saved. Please try again.")
            isFinishingSession = false
            return
        }

        completionState = updatedCompletion
        activeSession = nil
        contentState = .idle
        NotificationCenter.default.post(name: .dailyWorkflowDidFinish, object: nil)
    }

    func completeFinishingSession() {
        guard isFinishingSession else { return }

        isFinishingSession = false
        evaluate()
    }

    func setReminderCompleted(reminderID: String, completed: Bool) async {
        guard activeSession != nil,
            !isFinishingSession,
            !updatingReminderIDs.contains(reminderID)
        else {
            return
        }

        updatingReminderIDs.insert(reminderID)
        updateReminderCompletionLocally(reminderID: reminderID, completed: completed)
        await calendarService.setReminderCompleted(reminderID: reminderID, completed: completed)
        await reloadActiveSession(showLoadingIndicator: false)
        updatingReminderIDs.remove(reminderID)
    }

    func reloadActiveSession(showLoadingIndicator: Bool = true) async {
        guard let session = activeSession else { return }
        if showLoadingIndicator {
            contentState = .loading
        }

        let status = EKEventStore.authorizationStatus(for: .reminder)
        let hasAccess: Bool
        switch status {
        case .notDetermined:
            hasAccess = (try? await calendarService.requestAccess(to: .reminder)) == true
        case .fullAccess, .authorized:
            hasAccess = true
        case .denied, .restricted, .writeOnly:
            hasAccess = false
        @unknown default:
            hasAccess = false
        }

        guard hasAccess else {
            contentState = .permissionDenied
            return
        }

        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .day, for: session.date) else {
            contentState = .failure("Today’s reminder window could not be calculated.")
            return
        }

        let events = await calendarService.reminders(from: interval.start, to: interval.end)
        guard activeSession == session else { return }

        let items = events.compactMap { event -> DailyReminderItem? in
            guard case .reminder(let isCompleted) = event.type else { return nil }
            return DailyReminderItem(
                id: event.id,
                title: event.title,
                dueDate: event.start,
                isCompleted: isCompleted,
                listTitle: event.calendar.title
            )
        }
        contentState = .loaded(
            DailyReminderSections(
                items: items,
                sessionDate: session.date,
                calendar: calendar
            ))
    }

    private func updateReminderCompletionLocally(reminderID: String, completed: Bool) {
        guard let session = activeSession, case .loaded(let sections) = contentState else { return }

        let updatedItems = sections.all.map { item in
            guard item.id == reminderID else { return item }
            return DailyReminderItem(
                id: item.id,
                title: item.title,
                dueDate: item.dueDate,
                isCompleted: completed,
                listTitle: item.listTitle
            )
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            contentState = .loaded(
                DailyReminderSections(
                    items: updatedItems,
                    sessionDate: session.date,
                    calendar: .current
                )
            )
        }
    }

    private func updatePreferences(_ update: (inout DailyWorkflowPreferences) -> Void) {
        var updatedPreferences = preferences
        update(&updatedPreferences)
        updatedPreferences.morningPlanningMinutes = clampedMinutes(
            updatedPreferences.morningPlanningMinutes)
        updatedPreferences.eveningReviewMinutes = clampedMinutes(
            updatedPreferences.eveningReviewMinutes)

        do {
            try store.savePreferences(updatedPreferences)
            preferences = updatedPreferences
            evaluate()
        } catch {
            contentState = .failure("Your schedule could not be saved. Please try again.")
        }
    }

    private func clampedMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 0), 23 * 60 + 59)
    }

    private func evaluate(at date: Date = Date()) {
        evaluationTask?.cancel()
        evaluationTask = Task { [weak self] in
            await self?.evaluateNow(at: date)
        }
    }

    private func evaluateNow(at date: Date) async {
        timer?.invalidate()
        timer = nil

        if activeSession != nil {
            presentActiveSessionIfNeeded()
            return
        }

        if let kind = DailyWorkflowSchedule.dueWorkflow(
            at: date,
            preferences: preferences,
            completionState: completionState,
            calendar: .current
        ) {
            activeSession = DailyWorkflowSession(kind: kind, date: date)
            contentState = .loading
            NotificationCenter.default.post(name: .dailyWorkflowNeedsPresentation, object: nil)
            await reloadActiveSession()
            return
        }

        guard
            let nextDate = DailyWorkflowSchedule.nextEvaluation(
                after: date,
                preferences: preferences,
                completionState: completionState,
                calendar: .current
            )
        else { return }

        let timer = Timer(fire: nextDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
