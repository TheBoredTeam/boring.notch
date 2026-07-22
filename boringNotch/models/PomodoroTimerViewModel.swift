//
//  PomodoroTimerViewModel.swift
//  boringNotch
//

import AppKit
import Defaults
import SwiftUI
import UserNotifications

@MainActor
class PomodoroTimerViewModel: ObservableObject {
    static let shared = PomodoroTimerViewModel()

    private enum NotificationAuthorizationState {
        case unknown
        case granted
        case denied
    }

    @Published private(set) var currentPhase: PomodoroPhase = .focus
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var completedFocusSessions: Int = 0
    /// Drives whether the compact timer should remain visible in the closed notch.
    @Published private(set) var shouldShowCompactDisplay: Bool = false

    @Published private(set) var phaseCompleteHapticTick: Int = 0
    @Published private(set) var countdownHapticTick: Int = 0
    @Published private(set) var countdownFinalSecondHapticTick: Int = 0

    private var timerTask: Task<Void, Never>?
    /// Wall-clock anchor for the current countdown "segment" (handles resume/pause accurately).
    private var countdownSegmentStartDate: Date?
    /// Remaining seconds at `countdownSegmentStartDate` (so countdown haptics are correct after resume).
    private var countdownSegmentTotalSeconds: Int = 0
    /// Last elapsed second we already emitted haptics for.
    private var lastCountdownAnnouncedElapsedSeconds: Int = 0
    private var notificationAuthorizationState: NotificationAuthorizationState = .unknown
    private var isRequestingNotificationAuthorization: Bool = false
    private var pendingNotificationPhases: [PomodoroPhase] = []
    private var requestAuthorizationHandler: (@escaping (Bool) -> Void) -> Void
    private var addNotificationRequestHandler: (UNNotificationRequest) -> Void
    private var beepHandler: () -> Void

    var totalSecondsForCurrentPhase: Int {
        switch currentPhase {
        case .focus:
            return Defaults[.pomodoroFocusMinutes] * 60
        case .shortBreak:
            return Defaults[.pomodoroShortBreakMinutes] * 60
        case .longBreak:
            return Defaults[.pomodoroLongBreakMinutes] * 60
        }
    }

    var progress: Double {
        let total = totalSecondsForCurrentPhase
        guard total > 0 else { return 0 }
        return 1.0 - (Double(remainingSeconds) / Double(total))
    }

    var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var compactFormattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        if minutes > 0 {
            return seconds == 0 ? "\(minutes)m" : "\(minutes):\(String(format: "%02d", seconds))"
        }
        return "\(seconds)s"
    }

    private init() {
        requestAuthorizationHandler = { completion in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                completion(granted)
            }
        }
        addNotificationRequestHandler = { request in
            UNUserNotificationCenter.current().add(request)
        }
        beepHandler = {
            NSSound.beep()
        }
        migratePhaseAlertModeIfNeeded()
        remainingSeconds = Defaults[.pomodoroFocusMinutes] * 60
    }

    private func clearCountdownSegment() {
        countdownSegmentStartDate = nil
        countdownSegmentTotalSeconds = 0
        lastCountdownAnnouncedElapsedSeconds = 0
    }

    private func stopTimer(keepingCompactDisplay: Bool) {
        isRunning = false
        timerTask?.cancel()
        timerTask = nil
        clearCountdownSegment()
        shouldShowCompactDisplay = keepingCompactDisplay
    }

    private func migratePhaseAlertModeIfNeeded() {
        guard !Defaults[.pomodoroPhaseAlertLegacyMigrated] else { return }
        Defaults[.pomodoroPhaseAlertLegacyMigrated] = true
        if Defaults[.pomodoroNotifyOnPhaseComplete] {
            Defaults[.pomodoroPhaseAlertMode] = .system
        } else {
            Defaults[.pomodoroPhaseAlertMode] = .none
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        shouldShowCompactDisplay = true
        countdownSegmentStartDate = Date()
        countdownSegmentTotalSeconds = remainingSeconds
        lastCountdownAnnouncedElapsedSeconds = 0
        startTimerLoop()
    }

    func pause() {
        stopTimer(keepingCompactDisplay: true)
    }

    func reset() {
        stopTimer(keepingCompactDisplay: false)
        currentPhase = .focus
        completedFocusSessions = 0
        remainingSeconds = Defaults[.pomodoroFocusMinutes] * 60
        countdownFinalSecondHapticTick = 0
        countdownHapticTick = 0
    }

    func clampRemainingToPhaseDuration() {
        guard !isRunning else { return }
        let max = totalSecondsForCurrentPhase
        guard max > 0 else { return }
        if remainingSeconds > max {
            remainingSeconds = max
        }
    }

    func skip() {
        stopTimer(keepingCompactDisplay: true)
        advancePhase()
    }

    func toggleStartPause() {
        if isRunning {
            pause()
        } else {
            if remainingSeconds <= 0 {
                remainingSeconds = totalSecondsForCurrentPhase
            }
            start()
        }
    }

    private func startTimerLoop() {
        timerTask?.cancel()

        // Capture the segment anchor values now (on the main actor) so the background
        // task never needs to touch actor-isolated properties during its sleep.
        guard let segmentStartDate = countdownSegmentStartDate,
              countdownSegmentTotalSeconds > 0 else { return }
        let segmentTotal = countdownSegmentTotalSeconds

        // Use a detached task so the 1-second sleep runs on the cooperative thread pool,
        // not on the main actor. This prevents main-actor congestion (e.g. rapid notch
        // taps triggering animations) from starving the countdown.
        timerTask = Task.detached(priority: .userInitiated) { [weak self] in
            // Local elapsed tracker — updated off-main, written back on-main each tick.
            var lastAnnouncedElapsed = 0

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }

                // Pure arithmetic — no actor needed.
                let now = Date()
                let elapsedSeconds = Int(now.timeIntervalSince(segmentStartDate))
                let clampedElapsed = max(0, min(elapsedSeconds, segmentTotal))
                let newRemaining = max(0, segmentTotal - clampedElapsed)

                // Tally any haptic ticks for seconds we may have jumped over.
                var hapticTicks = 0
                var finalSecondTicks = 0
                if clampedElapsed > lastAnnouncedElapsed {
                    let crossedRemainingRange = (segmentTotal - clampedElapsed)...(segmentTotal - (lastAnnouncedElapsed + 1))
                    hapticTicks = Self.countOverlap(in: crossedRemainingRange, with: 2...5)
                    finalSecondTicks = Self.countOverlap(in: crossedRemainingRange, with: 1...1)
                    lastAnnouncedElapsed = clampedElapsed
                }

                // Single main-actor hop to publish all state changes for this tick.
                await MainActor.run { [weak self] in
                    guard let self, self.isRunning else { return }

                    self.lastCountdownAnnouncedElapsedSeconds = lastAnnouncedElapsed
                    self.remainingSeconds = newRemaining

                    if Defaults[.enableHaptics] && Defaults[.pomodoroHapticCountdown] {
                        if hapticTicks > 0      { self.countdownHapticTick += hapticTicks }
                        if finalSecondTicks > 0 { self.countdownFinalSecondHapticTick += finalSecondTicks }
                    }

                    if newRemaining <= 0 {
                        self.onPhaseComplete()
                    }
                }

                if newRemaining <= 0 { return }
            }
        }
    }

    nonisolated static func countOverlap(in source: ClosedRange<Int>, with target: ClosedRange<Int>) -> Int {
        let lower = max(source.lowerBound, target.lowerBound)
        let upper = min(source.upperBound, target.upperBound)
        guard lower <= upper else { return 0 }
        return upper - lower + 1
    }

    private func onPhaseComplete() {
        let completedPhase = currentPhase
        stopTimer(keepingCompactDisplay: false)

        if Defaults[.pomodoroSoundOnPhaseComplete] {
            beepHandler()
        }

        if Defaults[.enableHaptics], Defaults[.pomodoroHapticPhaseComplete] {
            phaseCompleteHapticTick += 1
        }

        let mode = Defaults[.pomodoroPhaseAlertMode]
        if mode == .inline || mode == .both {
            // Same mechanism as music track-change “inline” notifications: `expandingView` + auto-dismiss.
            BoringViewCoordinator.shared.toggleExpandingView(
                status: true,
                type: .pomodoro,
                pomodoroMessage: Self.inlineBannerMessage(forCompletedPhase: completedPhase)
            )
        }
        if mode == .system || mode == .both {
            sendCompletionNotification(forPhase: completedPhase)
        }

        let shouldAutoStart: Bool
        switch completedPhase {
        case .focus:
            shouldAutoStart = Defaults[.pomodoroAutoStartBreaks]
        case .shortBreak, .longBreak:
            shouldAutoStart = Defaults[.pomodoroAutoStartFocus]
        }

        advancePhase()

        if shouldAutoStart {
            start()
        }
    }

    private static func inlineBannerMessage(forCompletedPhase phase: PomodoroPhase) -> String {
        switch phase {
        case .focus:
            return NSLocalizedString(
                "pomodoro_inline_focus_complete",
                comment: "Pomodoro inline banner when focus block ends"
            )
        case .shortBreak:
            return NSLocalizedString(
                "pomodoro_inline_short_break_complete",
                comment: "Pomodoro inline banner when short break ends"
            )
        case .longBreak:
            return NSLocalizedString(
                "pomodoro_inline_long_break_complete",
                comment: "Pomodoro inline banner when long break ends"
            )
        }
    }

    private func advancePhase() {
        switch currentPhase {
        case .focus:
            completedFocusSessions += 1
            let every = max(1, Defaults[.pomodoroLongBreakEvery])
            if completedFocusSessions % every == 0 {
                currentPhase = .longBreak
            } else {
                currentPhase = .shortBreak
            }
        case .shortBreak, .longBreak:
            currentPhase = .focus
        }
        remainingSeconds = totalSecondsForCurrentPhase
    }

    private func sendCompletionNotification(forPhase phase: PomodoroPhase) {
        switch notificationAuthorizationState {
        case .granted:
            enqueueCompletionNotification(forPhase: phase)
        case .denied:
            break
        case .unknown:
            pendingNotificationPhases.append(phase)
            requestNotificationAuthorizationIfNeeded()
        }
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard !isRequestingNotificationAuthorization else { return }
        isRequestingNotificationAuthorization = true

        requestAuthorizationHandler { granted in
            Task { @MainActor in
                self.isRequestingNotificationAuthorization = false
                self.notificationAuthorizationState = granted ? .granted : .denied

                guard granted else {
                    self.pendingNotificationPhases.removeAll()
                    return
                }

                let queuedPhases = self.pendingNotificationPhases
                self.pendingNotificationPhases.removeAll()
                for queuedPhase in queuedPhases {
                    self.enqueueCompletionNotification(forPhase: queuedPhase)
                }
            }
        }
    }

    private func enqueueCompletionNotification(forPhase phase: PomodoroPhase) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("pomodoro_notification_title", comment: "Pomodoro notification title")
        content.sound = .default

        switch phase {
        case .focus:
            content.body = NSLocalizedString(
                "pomodoro_notify_focus_done",
                comment: "Pomodoro system notification body after focus"
            )
        case .shortBreak:
            content.body = NSLocalizedString(
                "pomodoro_notify_short_break_done",
                comment: "Pomodoro system notification body after short break"
            )
        case .longBreak:
            content.body = NSLocalizedString(
                "pomodoro_notify_long_break_done",
                comment: "Pomodoro system notification body after long break"
            )
        }

        let request = UNNotificationRequest(
            identifier: "pomodoro-phase-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        addNotificationRequestHandler(request)
    }

    /// Keeps Pomodoro panel visibility rules inside Pomodoro code.
    func shouldShowPanelInHome(
        panelEnabled: Bool,
        isSelectedInHome: Bool
    ) -> Bool {
        panelEnabled && isSelectedInHome
    }
}

#if DEBUG
extension PomodoroTimerViewModel {
    func _testSetPhase(_ phase: PomodoroPhase) {
        currentPhase = phase
        remainingSeconds = totalSecondsForCurrentPhase
    }

    func _testSetCompletedFocusSessions(_ value: Int) {
        completedFocusSessions = value
    }

    func _testTriggerPhaseCompletion() {
        onPhaseComplete()
    }

    func _testSetRemainingSeconds(_ value: Int) {
        remainingSeconds = value
    }

    func _testSendCompletionNotification(forPhase phase: PomodoroPhase) {
        sendCompletionNotification(forPhase: phase)
    }

    func _testConfigureNotificationHandlers(
        requestAuthorization: @escaping (@escaping (Bool) -> Void) -> Void,
        addRequest: @escaping (UNNotificationRequest) -> Void
    ) {
        requestAuthorizationHandler = requestAuthorization
        addNotificationRequestHandler = addRequest
    }

    func _testResetNotificationHandlersToSystem() {
        requestAuthorizationHandler = { completion in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                completion(granted)
            }
        }
        addNotificationRequestHandler = { request in
            UNUserNotificationCenter.current().add(request)
        }
    }

    func _testConfigureBeepHandler(_ handler: @escaping () -> Void) {
        beepHandler = handler
    }

    func _testResetBeepHandler() {
        beepHandler = {
            NSSound.beep()
        }
    }

    func _testResetNotificationAuthorizationState() {
        notificationAuthorizationState = .unknown
        isRequestingNotificationAuthorization = false
        pendingNotificationPhases.removeAll()
    }
}
#endif
