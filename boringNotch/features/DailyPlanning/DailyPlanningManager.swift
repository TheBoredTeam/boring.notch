import Combine
import Foundation
import AppKit

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

enum DailyConclusionPhase: Equatable {
    case review, writing, saving, filing
}

@MainActor
final class DailyPlanningManager: ObservableObject {
    static let shared = DailyPlanningManager()

    @Published private(set) var preferences: DailyWorkflowPreferences
    @Published private(set) var pendingSession: DailyWorkflowSession?
    @Published private(set) var activeSession: DailyWorkflowSession?
    @Published private(set) var finishingSession: DailyWorkflowSession?
    @Published private(set) var contentState: DailyPlanningContentState = .idle
    @Published private(set) var updatingReminderIDs: Set<String> = []
    @Published private(set) var reminderTransitions: [String: DailyReminderTransition] = [:]

    @Published private(set) var conclusionPreferences: DailyConclusionPreferences
    @Published private(set) var conclusionPhase: DailyConclusionPhase = .review
    @Published var conclusionText = ""
    @Published private(set) var conclusionError: String?
    @Published private(set) var conclusionSettingsError: String?
    @Published private(set) var savedConclusionURL: URL?
    private var conclusionTask: Task<Void, Never>?

    var isConclusionActive: Bool { conclusionPhase != .review }
    var isSavingConclusion: Bool { conclusionPhase == .saving || conclusionPhase == .filing }
    var offersConclusion: Bool {
        activeSession?.kind == .eveningReview && conclusionPreferences.isEnabled
    }

    var isPresenting: Bool { activeSession != nil }
    var isAwaitingPresentation: Bool { pendingSession != nil }
    var isFinishingSession: Bool { finishingSession != nil }

    var onNeedsPresentation: (() -> Void)?
    var onDidFinish: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let store: DailyWorkflowPreferencesStore
    private let reminderService: DailyReminderProviding
    private var completionState: DailyWorkflowCompletionState
    private var timer: Timer?
    private var evaluationTask: Task<Void, Never>?
    private var eventStoreObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var applicationActivationObserver: NSObjectProtocol?
    private var hasStarted = false

    init(
        store: DailyWorkflowPreferencesStore = DailyWorkflowPreferencesStore(),
        reminderService: DailyReminderProviding? = nil
    ) {
        self.store = store
        self.reminderService = reminderService ?? EventKitDailyReminderService()
        preferences = store.loadPreferences()
        conclusionPreferences = store.loadConclusionPreferences()
        completionState = store.loadCompletionState()
    }

    deinit {
        timer?.invalidate()
        evaluationTask?.cancel()
        if let eventStoreObserver {
            NotificationCenter.default.removeObserver(eventStoreObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let applicationActivationObserver {
            NotificationCenter.default.removeObserver(applicationActivationObserver)
        }
    }

    func start() {
        guard !hasStarted else {
            presentActiveSessionIfNeeded()
            return
        }
        hasStarted = true
        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: reminderService.changeNotification,
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
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
        applicationActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
        #if DEBUG
        if CommandLine.arguments.contains("--preview-evening-review") {
            conclusionPreferences.isEnabled = true
            activeSession = DailyWorkflowSession(kind: .eveningReview, date: Date())
            contentState = .loading
            onNeedsPresentation?()
            Task { [weak self] in await self?.reloadActiveSession() }
            return
        }
        #endif
        evaluate()
    }

    func presentActiveSessionIfNeeded() {
        guard activeSession != nil else { return }
        onNeedsPresentation?()
    }

    @discardableResult
    func activatePendingSession(requestPresentation: Bool = true) -> Bool {
        guard activeSession == nil, let pendingSession else { return false }

        self.pendingSession = nil
        activeSession = pendingSession
        contentState = .loading
        if requestPresentation { onNeedsPresentation?() }

        Task { [weak self] in
            await self?.reloadActiveSession()
        }
        return true
    }

    func returnActiveSessionToPrompt() {
        guard let activeSession, !isFinishingSession, !isSavingConclusion else { return }

        pendingSession = activeSession
        self.activeSession = nil
        contentState = .idle
        updatingReminderIDs.removeAll()
        reminderTransitions.removeAll()
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

    func setConclusionEnabled(_ enabled: Bool) {
        var updated = conclusionPreferences
        updated.isEnabled = enabled
        saveConclusionPreferences(updated)
    }

    func setConclusionDirectory(_ url: URL) {
        var updated = conclusionPreferences
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            updated.directoryBookmark = try url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            updated.directoryPath = url.path
            saveConclusionPreferences(updated)
        } catch {
            conclusionSettingsError = "Folder access could not be saved. Please choose the folder again."
        }
    }

    private func saveConclusionPreferences(_ updated: DailyConclusionPreferences) {
        do {
            try store.saveConclusionPreferences(updated)
            conclusionPreferences = updated
            conclusionSettingsError = nil
        } catch {
            conclusionSettingsError = "Settings could not be saved. Please try again."
        }
    }

    func advanceToConclusion() {
        guard offersConclusion, conclusionPhase == .review, !isFinishingSession else { return }
        conclusionPhase = .writing
    }

    func openConclusionSettings() {
        guard conclusionPhase == .writing else { return }
        returnActiveSessionToPrompt()
        onOpenSettings?()
    }

    func returnToReview() {
        guard conclusionPhase == .writing else { return }
        conclusionPhase = .review
        conclusionError = nil
    }

    func saveConclusion() {
        guard let session = activeSession, session.kind == .eveningReview,
              conclusionPhase == .writing else { return }
        if savedConclusionURL != nil {
            beginFinishingActiveSession()
            return
        }
        if conclusionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            beginFinishingActiveSession()
            return
        }
        guard let bookmark = conclusionPreferences.directoryBookmark else {
            conclusionError = "Choose a diary folder in Settings → Planning & Review, then try again."
            return
        }
        let text = conclusionText
        conclusionError = nil
        conclusionPhase = .saving
        conclusionTask = Task { [weak self] in
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    var stale = false
                    let directory = try URL(resolvingBookmarkData: bookmark,
                        options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
                    guard !stale else { throw CocoaError(.fileReadNoPermission) }
                    let accessing = directory.startAccessingSecurityScopedResource()
                    defer { if accessing { directory.stopAccessingSecurityScopedResource() } }
                    return try DailyConclusionStore().save(text: text, date: session.date, directory: directory)
                }.value
                guard let self, self.activeSession == session else { return }
                self.savedConclusionURL = url
                self.conclusionPhase = .filing
            } catch {
                guard let self, self.activeSession == session else { return }
                self.conclusionPhase = .writing
                self.conclusionError = "Couldn’t save your diary. Check the folder in Settings → Planning & Review, then try again. Your text is still here."
            }
        }
    }

    func completeConclusionAnimation() {
        guard conclusionPhase == .filing, savedConclusionURL != nil else { return }
        beginFinishingActiveSession()
    }

    func beginFinishingActiveSession() {
        guard let activeSession, finishingSession == nil else { return }
        guard !offersConclusion || savedConclusionURL != nil
            || (conclusionPhase == .writing && conclusionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        else { return }
        finishingSession = activeSession
    }

    func finalizeActiveSession() {
        guard let session = finishingSession, activeSession == session else { return }

        var updatedCompletion = completionState
        updatedCompletion.markCompleted(session.kind, on: session.date, calendar: .current)

        do {
            try store.saveCompletionState(updatedCompletion)
        } catch {
            contentState = .failure("Your completion could not be saved. Please try again.")
            finishingSession = nil
            if savedConclusionURL != nil {
                conclusionPhase = .writing
                conclusionError = "Your diary was saved, but the review could not be completed. Try finishing again."
            }
            return
        }

        completionState = updatedCompletion
        activeSession = nil
        contentState = .idle
        onDidFinish?()
    }

    func completeFinishingSession() {
        guard finishingSession != nil else { return }

        finishingSession = nil
        conclusionPhase = .review
        conclusionText = ""
        conclusionError = nil
        savedConclusionURL = nil
        conclusionTask = nil
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

        do {
            try await reminderService.setCompleted(completed, reminderID: reminderID)
        } catch {
            clearReminderTransition(reminderID: reminderID, sessionID: sessionID)
            if activeSession?.id == sessionID {
                contentState = .failure("The reminder could not be updated. Please try again.")
            }
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(420))

            guard activeSession?.id == sessionID else {
                clearReminderTransition(reminderID: reminderID, sessionID: sessionID)
                return
            }

            if animateSectionTransfer {
                setReminderTransitionPhase(
                    .hidden,
                    reminderID: reminderID,
                    sessionID: sessionID
                )

                try await Task.sleep(for: .milliseconds(180))
                guard activeSession?.id == sessionID else {
                    clearReminderTransition(reminderID: reminderID, sessionID: sessionID)
                    return
                }

                updateReminderCompletionLocally(
                    reminderID: reminderID,
                    completed: completed
                )

                setReminderTransitionPhase(
                    .revealed,
                    reminderID: reminderID,
                    sessionID: sessionID
                )

                try await Task.sleep(for: .milliseconds(180))
            } else {
                updateReminderCompletionLocally(
                    reminderID: reminderID,
                    completed: completed
                )
            }
        } catch is CancellationError {
            clearReminderTransition(reminderID: reminderID, sessionID: sessionID)
            await reconcileReminderUpdatesIfNeeded(for: sessionID)
            return
        } catch {
            clearReminderTransition(reminderID: reminderID, sessionID: sessionID)
            await reconcileReminderUpdatesIfNeeded(for: sessionID)
            return
        }

        clearReminderTransition(reminderID: reminderID, sessionID: sessionID)
        await reconcileReminderUpdatesIfNeeded(for: sessionID)
    }

    func reloadActiveSession(showLoadingIndicator: Bool = true) async {
        guard let session = activeSession else { return }
        if showLoadingIndicator {
            contentState = .loading
        }

        let hasAccess: Bool
        switch reminderService.authorization {
        case .notDetermined:
            hasAccess = (try? await reminderService.requestAccess()) == true
        case .authorized:
            hasAccess = true
        case .denied:
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

        let items = await reminderService.reminders(from: interval.start, to: interval.end)
        guard activeSession == session else { return }

        contentState = .loaded(
            DailyReminderSections(
                items: items,
                sessionDate: session.date,
                calendar: calendar
            ))
    }

    private func updateReminderCompletionLocally(
        reminderID: String,
        completed: Bool
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

        update()
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

        if pendingSession != nil {
            return
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
