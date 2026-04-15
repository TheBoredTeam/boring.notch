import Defaults
import UserNotifications
import XCTest
@testable import boringNotch

@MainActor
final class PomodoroTimerViewModelTests: XCTestCase {
    private struct PomodoroDefaultsSnapshot {
        let focusMinutes: Int
        let shortBreakMinutes: Int
        let longBreakMinutes: Int
        let longBreakEvery: Int
        let autoStartBreaks: Bool
        let autoStartFocus: Bool
        let phaseAlertMode: PomodoroPhaseAlertMode
        let soundOnPhaseComplete: Bool
        let enableHaptics: Bool
        let hapticPhaseComplete: Bool
        let hapticCountdown: Bool
    }

    private var defaultsSnapshot: PomodoroDefaultsSnapshot!
    private var timer: PomodoroTimerViewModel { .shared }
    private var requestAuthorizationCalls = 0
    private var pendingAuthorizationCompletion: ((Bool) -> Void)?
    private var enqueuedRequests: [UNNotificationRequest] = []
    private var beepCalls = 0

    override func setUpWithError() throws {
        defaultsSnapshot = PomodoroDefaultsSnapshot(
            focusMinutes: Defaults[.pomodoroFocusMinutes],
            shortBreakMinutes: Defaults[.pomodoroShortBreakMinutes],
            longBreakMinutes: Defaults[.pomodoroLongBreakMinutes],
            longBreakEvery: Defaults[.pomodoroLongBreakEvery],
            autoStartBreaks: Defaults[.pomodoroAutoStartBreaks],
            autoStartFocus: Defaults[.pomodoroAutoStartFocus],
            phaseAlertMode: Defaults[.pomodoroPhaseAlertMode],
            soundOnPhaseComplete: Defaults[.pomodoroSoundOnPhaseComplete],
            enableHaptics: Defaults[.enableHaptics],
            hapticPhaseComplete: Defaults[.pomodoroHapticPhaseComplete],
            hapticCountdown: Defaults[.pomodoroHapticCountdown]
        )
        Defaults[.pomodoroFocusMinutes] = 25
        Defaults[.pomodoroShortBreakMinutes] = 5
        Defaults[.pomodoroLongBreakMinutes] = 15
        Defaults[.pomodoroLongBreakEvery] = 4
        Defaults[.pomodoroAutoStartBreaks] = false
        Defaults[.pomodoroAutoStartFocus] = false
        Defaults[.pomodoroPhaseAlertMode] = .none
        Defaults[.pomodoroSoundOnPhaseComplete] = false
        Defaults[.enableHaptics] = true
        Defaults[.pomodoroHapticPhaseComplete] = true
        Defaults[.pomodoroHapticCountdown] = true

        timer.reset()
        timer._testSetPhase(.focus)
        timer._testSetCompletedFocusSessions(0)
        timer._testResetNotificationAuthorizationState()
        timer._testResetNotificationHandlersToSystem()
        timer._testResetBeepHandler()
        BoringViewCoordinator.shared.expandingView = .init()

        requestAuthorizationCalls = 0
        pendingAuthorizationCompletion = nil
        enqueuedRequests = []
        beepCalls = 0
    }

    override func tearDownWithError() throws {
        timer.pause()
        timer.reset()
        timer._testResetNotificationAuthorizationState()
        timer._testResetNotificationHandlersToSystem()
        timer._testResetBeepHandler()
        BoringViewCoordinator.shared.expandingView = .init()

        Defaults[.pomodoroFocusMinutes] = defaultsSnapshot.focusMinutes
        Defaults[.pomodoroShortBreakMinutes] = defaultsSnapshot.shortBreakMinutes
        Defaults[.pomodoroLongBreakMinutes] = defaultsSnapshot.longBreakMinutes
        Defaults[.pomodoroLongBreakEvery] = defaultsSnapshot.longBreakEvery
        Defaults[.pomodoroAutoStartBreaks] = defaultsSnapshot.autoStartBreaks
        Defaults[.pomodoroAutoStartFocus] = defaultsSnapshot.autoStartFocus
        Defaults[.pomodoroPhaseAlertMode] = defaultsSnapshot.phaseAlertMode
        Defaults[.pomodoroSoundOnPhaseComplete] = defaultsSnapshot.soundOnPhaseComplete
        Defaults[.enableHaptics] = defaultsSnapshot.enableHaptics
        Defaults[.pomodoroHapticPhaseComplete] = defaultsSnapshot.hapticPhaseComplete
        Defaults[.pomodoroHapticCountdown] = defaultsSnapshot.hapticCountdown
    }

    func testResetRestoresInitialFocusState() {
        timer.skip()
        XCTAssertNotEqual(timer.currentPhase, .focus)

        timer.reset()

        XCTAssertEqual(timer.currentPhase, .focus)
        XCTAssertEqual(timer.completedFocusSessions, 0)
        XCTAssertEqual(timer.remainingSeconds, Defaults[.pomodoroFocusMinutes] * 60)
        XCTAssertFalse(timer.isRunning)
        XCTAssertFalse(timer.shouldShowCompactDisplay)
    }

    func testSkipTransitionsFocusToShortBreakToFocusToLongBreak() {
        Defaults[.pomodoroLongBreakEvery] = 2
        timer.reset()

        timer.skip()
        XCTAssertEqual(timer.currentPhase, .shortBreak)
        XCTAssertEqual(timer.completedFocusSessions, 1)
        XCTAssertEqual(timer.remainingSeconds, Defaults[.pomodoroShortBreakMinutes] * 60)

        timer.skip()
        XCTAssertEqual(timer.currentPhase, .focus)
        XCTAssertEqual(timer.completedFocusSessions, 1)
        XCTAssertEqual(timer.remainingSeconds, Defaults[.pomodoroFocusMinutes] * 60)

        timer.skip()
        XCTAssertEqual(timer.currentPhase, .longBreak)
        XCTAssertEqual(timer.completedFocusSessions, 2)
        XCTAssertEqual(timer.remainingSeconds, Defaults[.pomodoroLongBreakMinutes] * 60)
    }

    func testToggleStartPauseUpdatesRunningAndCompactState() {
        timer.reset()
        timer.toggleStartPause()
        XCTAssertTrue(timer.isRunning)
        XCTAssertTrue(timer.shouldShowCompactDisplay)

        timer.toggleStartPause()
        XCTAssertFalse(timer.isRunning)
        XCTAssertTrue(timer.shouldShowCompactDisplay)
    }

    func testClampRemainingToPhaseDurationWhenPaused() {
        timer.reset()
        Defaults[.pomodoroFocusMinutes] = 1
        timer.clampRemainingToPhaseDuration()
        XCTAssertEqual(timer.remainingSeconds, 60)
    }

    func testCompactFormattingAcrossMinuteAndSecondBoundaries() {
        timer._testSetRemainingSeconds(300)
        XCTAssertEqual(timer.compactFormattedTime, "5m")

        timer._testSetRemainingSeconds(305)
        XCTAssertEqual(timer.compactFormattedTime, "5:05")

        timer._testSetRemainingSeconds(45)
        XCTAssertEqual(timer.compactFormattedTime, "45s")
    }

    func testCountOverlapHandlesEdgeCases() {
        XCTAssertEqual(PomodoroTimerViewModel.countOverlap(in: -5...10, with: 2...5), 4)
        XCTAssertEqual(PomodoroTimerViewModel.countOverlap(in: 6...9, with: 2...5), 0)
        XCTAssertEqual(PomodoroTimerViewModel.countOverlap(in: 1...1, with: 1...1), 1)
    }

    func testPhaseCompletionFromFocusAdvancesToShortBreakWhenAutoStartOff() {
        timer.start()
        XCTAssertTrue(timer.shouldShowCompactDisplay)

        timer._testSetPhase(.focus)
        timer._testSetCompletedFocusSessions(0)
        timer._testTriggerPhaseCompletion()

        XCTAssertEqual(timer.currentPhase, .shortBreak)
        XCTAssertEqual(timer.completedFocusSessions, 1)
        XCTAssertFalse(timer.isRunning)
        XCTAssertFalse(timer.shouldShowCompactDisplay)
    }

    func testPhaseCompletionFromFocusAutoStartsBreakWhenEnabled() {
        Defaults[.pomodoroAutoStartBreaks] = true
        timer._testSetPhase(.focus)
        timer._testSetCompletedFocusSessions(0)

        timer._testTriggerPhaseCompletion()

        XCTAssertEqual(timer.currentPhase, .shortBreak)
        XCTAssertTrue(timer.isRunning)
        XCTAssertTrue(timer.shouldShowCompactDisplay)
        timer.pause()
    }

    func testPhaseCompletionFromBreakAutoStartsFocusWhenEnabled() {
        Defaults[.pomodoroAutoStartFocus] = true
        timer._testSetPhase(.shortBreak)
        timer._testSetCompletedFocusSessions(1)

        timer._testTriggerPhaseCompletion()

        XCTAssertEqual(timer.currentPhase, .focus)
        XCTAssertEqual(timer.completedFocusSessions, 1)
        XCTAssertTrue(timer.isRunning)
        timer.pause()
    }

    func testPhaseCompletionUsesLongBreakCadence() {
        Defaults[.pomodoroLongBreakEvery] = 2
        timer._testSetPhase(.focus)
        timer._testSetCompletedFocusSessions(1)

        timer._testTriggerPhaseCompletion()

        XCTAssertEqual(timer.currentPhase, .longBreak)
        XCTAssertEqual(timer.completedFocusSessions, 2)
        XCTAssertEqual(timer.remainingSeconds, Defaults[.pomodoroLongBreakMinutes] * 60)
    }

    func testPhaseCompletionBeepRespectsSetting() {
        timer._testConfigureBeepHandler { [weak self] in
            self?.beepCalls += 1
        }
        timer._testSetPhase(.focus)

        Defaults[.pomodoroSoundOnPhaseComplete] = false
        timer._testTriggerPhaseCompletion()
        XCTAssertEqual(beepCalls, 0)

        Defaults[.pomodoroSoundOnPhaseComplete] = true
        timer._testSetPhase(.focus)
        timer._testTriggerPhaseCompletion()
        XCTAssertEqual(beepCalls, 1)
    }

    func testPhaseCompletionHapticTickRespectsSettings() {
        timer._testSetPhase(.focus)
        let baseline = timer.phaseCompleteHapticTick

        Defaults[.enableHaptics] = true
        Defaults[.pomodoroHapticPhaseComplete] = true
        timer._testTriggerPhaseCompletion()
        XCTAssertEqual(timer.phaseCompleteHapticTick, baseline + 1)

        timer._testSetPhase(.focus)
        Defaults[.pomodoroHapticPhaseComplete] = false
        timer._testTriggerPhaseCompletion()
        XCTAssertEqual(timer.phaseCompleteHapticTick, baseline + 1)
    }

    func testPhaseCompletionInlineBannerShownInInlineMode() async {
        Defaults[.pomodoroPhaseAlertMode] = .inline
        timer._testSetPhase(.focus)
        BoringViewCoordinator.shared.expandingView = .init()

        timer._testTriggerPhaseCompletion()
        await Task.yield()

        let view = BoringViewCoordinator.shared.expandingView
        XCTAssertTrue(view.show)
        if case .pomodoro = view.type {} else {
            XCTFail("Expected pomodoro expanding view type")
        }
        XCTAssertFalse(view.pomodoroMessage.isEmpty)
    }

    func testPhaseCompletionDoesNotShowInlineBannerInSystemMode() {
        Defaults[.pomodoroPhaseAlertMode] = .system
        timer._testSetPhase(.focus)
        BoringViewCoordinator.shared.expandingView = .init()

        timer._testTriggerPhaseCompletion()

        XCTAssertFalse(BoringViewCoordinator.shared.expandingView.show)
    }

    func testPhaseCompletionSystemAlertSendsNotification() async {
        Defaults[.pomodoroPhaseAlertMode] = .system
        timer._testSetPhase(.focus)
        timer._testConfigureNotificationHandlers(
            requestAuthorization: { [weak self] completion in
                guard let self else { return }
                requestAuthorizationCalls += 1
                completion(true)
            },
            addRequest: { [weak self] request in
                self?.enqueuedRequests.append(request)
            }
        )

        timer._testTriggerPhaseCompletion()
        await Task.yield()

        XCTAssertEqual(requestAuthorizationCalls, 1)
        XCTAssertEqual(enqueuedRequests.count, 1)
    }

    func testPhaseCompletionBothModeShowsInlineAndSendsNotification() async {
        Defaults[.pomodoroPhaseAlertMode] = .both
        timer._testSetPhase(.focus)
        BoringViewCoordinator.shared.expandingView = .init()
        timer._testConfigureNotificationHandlers(
            requestAuthorization: { [weak self] completion in
                guard let self else { return }
                requestAuthorizationCalls += 1
                completion(true)
            },
            addRequest: { [weak self] request in
                self?.enqueuedRequests.append(request)
            }
        )

        timer._testTriggerPhaseCompletion()
        await Task.yield()

        XCTAssertTrue(BoringViewCoordinator.shared.expandingView.show)
        if case .pomodoro = BoringViewCoordinator.shared.expandingView.type {} else {
            XCTFail("Expected pomodoro expanding view type")
        }
        XCTAssertEqual(requestAuthorizationCalls, 1)
        XCTAssertEqual(enqueuedRequests.count, 1)
    }

    func testPhaseCompletionNoneModeSendsNoInlineOrSystemAlert() async {
        Defaults[.pomodoroPhaseAlertMode] = .none
        timer._testSetPhase(.focus)
        BoringViewCoordinator.shared.expandingView = .init()
        timer._testConfigureNotificationHandlers(
            requestAuthorization: { [weak self] completion in
                guard let self else { return }
                requestAuthorizationCalls += 1
                completion(true)
            },
            addRequest: { [weak self] request in
                self?.enqueuedRequests.append(request)
            }
        )

        timer._testTriggerPhaseCompletion()
        await Task.yield()

        XCTAssertFalse(BoringViewCoordinator.shared.expandingView.show)
        XCTAssertEqual(requestAuthorizationCalls, 0)
        XCTAssertEqual(enqueuedRequests.count, 0)
    }

    func testTimerLoopCompletesSingleSecondCountdown() async {
        Defaults[.pomodoroPhaseAlertMode] = .none
        Defaults[.pomodoroAutoStartBreaks] = false
        timer.reset()
        timer._testSetPhase(.focus)
        timer._testSetRemainingSeconds(1)

        timer.start()
        try? await Task.sleep(for: .milliseconds(1300))

        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.currentPhase, .shortBreak)
    }

    func testTimerLoopCountdownHapticsNearEnd() async {
        Defaults[.pomodoroPhaseAlertMode] = .none
        Defaults[.pomodoroAutoStartBreaks] = false
        Defaults[.enableHaptics] = true
        Defaults[.pomodoroHapticCountdown] = true
        timer.reset()
        timer._testSetPhase(.focus)
        timer._testSetRemainingSeconds(5)
        let baselineCountdown = timer.countdownHapticTick
        let baselineFinal = timer.countdownFinalSecondHapticTick

        timer.start()
        try? await Task.sleep(for: .milliseconds(5300))

        XCTAssertGreaterThanOrEqual(timer.countdownHapticTick, baselineCountdown + 3)
        XCTAssertGreaterThanOrEqual(timer.countdownFinalSecondHapticTick, baselineFinal + 1)
        XCTAssertFalse(timer.isRunning)
    }

    func testNotificationAuthorizationRequestedOnceThenCachedAfterGrant() async {
        timer._testConfigureNotificationHandlers(
            requestAuthorization: { [weak self] completion in
                guard let self else { return }
                requestAuthorizationCalls += 1
                pendingAuthorizationCompletion = completion
            },
            addRequest: { [weak self] request in
                self?.enqueuedRequests.append(request)
            }
        )

        timer._testSendCompletionNotification(forPhase: .focus)
        timer._testSendCompletionNotification(forPhase: .shortBreak)

        XCTAssertEqual(requestAuthorizationCalls, 1)
        XCTAssertEqual(enqueuedRequests.count, 0)
        XCTAssertNotNil(pendingAuthorizationCompletion)

        pendingAuthorizationCompletion?(true)
        await Task.yield()

        XCTAssertEqual(enqueuedRequests.count, 2)
        XCTAssertEqual(requestAuthorizationCalls, 1)

        timer._testSendCompletionNotification(forPhase: .longBreak)
        XCTAssertEqual(requestAuthorizationCalls, 1)
        XCTAssertEqual(enqueuedRequests.count, 3)
    }

    func testNotificationQueueClearedAfterDeniedAuthorization() async {
        timer._testConfigureNotificationHandlers(
            requestAuthorization: { [weak self] completion in
                guard let self else { return }
                requestAuthorizationCalls += 1
                pendingAuthorizationCompletion = completion
            },
            addRequest: { [weak self] request in
                self?.enqueuedRequests.append(request)
            }
        )

        timer._testSendCompletionNotification(forPhase: .focus)
        timer._testSendCompletionNotification(forPhase: .shortBreak)
        XCTAssertEqual(requestAuthorizationCalls, 1)

        pendingAuthorizationCompletion?(false)
        await Task.yield()

        XCTAssertEqual(enqueuedRequests.count, 0)
        timer._testSendCompletionNotification(forPhase: .longBreak)
        XCTAssertEqual(requestAuthorizationCalls, 1)
        XCTAssertEqual(enqueuedRequests.count, 0)
    }
}
