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

enum DailyReminderTransitionPhase: Equatable {
    case animatingControl
    case hidden
    case revealed
}

struct DailyReminderTransition: Equatable {
    let sessionID: String
    let targetCompletion: Bool
    var phase: DailyReminderTransitionPhase
}

@MainActor
final class DailyPlanningManager: ObservableObject {
    static let shared = DailyPlanningManager()

    @Published private(set) var preferences: DailyWorkflowPreferences
    @Published private(set) var pendingSession: DailyWorkflowSession?
    @Published private(set) var activeSession: DailyWorkflowSession?
    @Published private(set) var contentState: DailyPlanningContentState = .idle
    @Published private(set) var isFinishingSession = false
    @Published private(set) var updatingReminderIDs: Set<String> = []
    @Published private(set) var reminderTransitions: [String: DailyReminderTransition] = [:]

    var isPresenting: Bool { activeSession != nil }
    var isAwaitingPresentation: Bool { pendingSession != nil }

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
                guard let self, self.activeSession != nil, self.updatingReminderIDs.isEmpty else {
                    return
                }
                await self.reloadActiveSession(showLoadingIndicator: false)
            }
        }
        evaluate()
    }

    func presentActiveSessionIfNeeded() {
        guard activeSession != nil else { return }
        NotificationCenter.default.post(name: .dailyWorkflowNeedsPresentation, object: nil)
    }

    @discardableResult
    func activatePendingSession(at date: Date = Date()) -> Bool {
        guard activeSession == nil, pendingSession != nil else { return false }

        guard let kind = DailyWorkflowSchedule.dueWorkflow(
            at: date,
            preferences: preferences,
            completionState: completionState,
            calendar: .current
        ) else {
            self.pendingSession = nil
            evaluate(at: date)
            return false
        }

        self.pendingSession = nil
        activeSession = DailyWorkflowSession(kind: kind, date: date)
        contentState = .loading
        NotificationCenter.default.post(name: .dailyWorkflowNeedsPresentation, object: nil)

        Task { [weak self] in
            await self?.reloadActiveSession()
        }
        return true
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

    func setReminderCompleted(
        reminderID: String,
        completed: Bool,
        animateSectionTransfer: Bool
    ) async {
        guard let session = activeSession,
            !isFinishingSession,
            !updatingReminderIDs.contains(reminderID)
        else {
            return
        }

        let sessionID = session.id
        updatingReminderIDs.insert(reminderID)
        reminderTransitions[reminderID] = DailyReminderTransition(
            sessionID: sessionID,
            targetCompletion: completed,
            phase: .animatingControl
        )

        let saveTask = Task { [calendarService] in
            await calendarService.setReminderCompleted(
                reminderID: reminderID,
                completed: completed
            )
        }

        do {
            try await Task.sleep(for: .milliseconds(420))

            guard activeSession?.id == sessionID else {
                await saveTask.value
                clearReminderTransition(reminderID: reminderID, sessionID: sessionID)
                return
            }

            if animateSectionTransfer {
                withAnimation(.easeOut(duration: 0.18)) {
                    setReminderTransitionPhase(
                        .hidden,
                        reminderID: reminderID,
                        sessionID: sessionID
                    )
                }

                try await Task.sleep(for: .milliseconds(180))
                guard activeSession?.id == sessionID else {
                    await saveTask.value
                    clearReminderTransition(reminderID: reminderID, sessionID: sessionID)
                    return
                }

                updateReminderCompletionLocally(
                    reminderID: reminderID,
                    completed: completed,
                    animated: false
                )

                withAnimation(.easeIn(duration: 0.18)) {
                    setReminderTransitionPhase(
                        .revealed,
                        reminderID: reminderID,
                        sessionID: sessionID
                    )
                }

                try await Task.sleep(for: .milliseconds(180))
            } else {
                updateReminderCompletionLocally(
                    reminderID: reminderID,
                    completed: completed
                )
            }
        } catch is CancellationError {
            await saveTask.value
            clearReminderTransition(reminderID: reminderID, sessionID: sessionID)
            await reconcileReminderUpdatesIfNeeded(for: sessionID)
            return
        } catch {
            await saveTask.value
            clearReminderTransition(reminderID: reminderID, sessionID: sessionID)
            await reconcileReminderUpdatesIfNeeded(for: sessionID)
            return
        }

        await saveTask.value
        clearReminderTransition(reminderID: reminderID, sessionID: sessionID)
        await reconcileReminderUpdatesIfNeeded(for: sessionID)
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

    private func updateReminderCompletionLocally(
        reminderID: String,
        completed: Bool,
        animated: Bool = true
    ) {
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

        let update = {
            self.contentState = .loaded(
                DailyReminderSections(
                    items: updatedItems,
                    sessionDate: session.date,
                    calendar: .current
                )
            )
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.22), update)
        } else {
            update()
        }
    }

    private func setReminderTransitionPhase(
        _ phase: DailyReminderTransitionPhase,
        reminderID: String,
        sessionID: String
    ) {
        guard var transition = reminderTransitions[reminderID],
            transition.sessionID == sessionID
        else {
            return
        }

        transition.phase = phase
        reminderTransitions[reminderID] = transition
    }

    private func clearReminderTransition(reminderID: String, sessionID: String) {
        if reminderTransitions[reminderID]?.sessionID == sessionID {
            reminderTransitions.removeValue(forKey: reminderID)
        }
        updatingReminderIDs.remove(reminderID)
    }

    private func reconcileReminderUpdatesIfNeeded(for sessionID: String) async {
        guard updatingReminderIDs.isEmpty, activeSession?.id == sessionID else { return }
        await reloadActiveSession(showLoadingIndicator: false)
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

        let dueKind = DailyWorkflowSchedule.dueWorkflow(
            at: date,
            preferences: preferences,
            completionState: completionState,
            calendar: .current
        )

        if let pendingSession {
            guard dueKind != pendingSession.kind else { return }
            self.pendingSession = nil
        }

        if let kind = dueKind {
            pendingSession = DailyWorkflowSession(kind: kind, date: date)
            contentState = .idle
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
