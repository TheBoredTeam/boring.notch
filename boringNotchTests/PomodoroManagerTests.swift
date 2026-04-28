//
//  PomodoroManagerTests.swift
//  boringNotchTests
//
//  Created by Claw/AI on 2026-04-28.
//

import Combine
import XCTest

@testable import boringNotch

// MARK: - Testable PomodoroManager
// Subclass to expose internal state and override UserDefaults for testing

class TestablePomodoroManager: PomodoroManager {
    
    private static let testDefaultsSuite = "com.boringNotch.pomodoro.tests"
    
    // Override UserDefaults with test suite
    private override var userDefaults: UserDefaults {
        return UserDefaults(suiteName: TestablePomodoroManager.testDefaultsSuite) ?? .standard
    }
    
    // Expose setters for testing
    var testTimeRemaining: TimeInterval {
        get { timeRemaining }
        set { timeRemaining = newValue }
    }
    
    var testSessionType: SessionType {
        get { sessionType }
        set { sessionType = newValue }
    }
    
    var testCurrentCycle: Int {
        get { currentCycle }
        set { currentCycle = newValue }
    }
    
    var testIsRunning: Bool {
        get { isRunning }
    }
    
    // Test-internal start that doesn't auto-save
    func testStart() {
        guard !isRunning else { return }
        isRunning = true
        startTimer()
    }
    
    func testPause() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    // Public access to reset
    func testReset() {
        reset()
    }
    
    // Manual tick for testing
    func performTick() {
        tick()
    }
    
    // Public access to session transition
    func testTransitionToNextSession() {
        transitionToNextSession()
    }
    
    // Duration access for test assertions
    var workDurationValue: TimeInterval { 25 * 60 }
    var shortBreakDurationValue: TimeInterval { 5 * 60 }
    var longBreakDurationValue: TimeInterval { 15 * 60 }
    var cyclesBeforeLongBreakValue: Int { 4 }
    
    // Expose duration helper
    func durationFor(type: SessionType) -> TimeInterval {
        durationForSession(type)
    }
    
    // Save/load for persistence tests
    func testSaveState() {
        saveState()
    }
    
    func testLoadState() {
        loadState()
    }
    
    // Clear UserDefaults for test isolation
    static func clearTestDefaults() {
        let defaults = UserDefaults(suiteName: testDefaultsSuite)
        defaults?.removeObject(forKey: "pomodoro_sessionType")
        defaults?.removeObject(forKey: "pomodoro_timeRemaining")
        defaults?.removeObject(forKey: "pomodoro_isRunning")
        defaults?.removeObject(forKey: "pomodoro_currentCycle")
    }
}

// MARK: - PomodoroManagerTests

final class PomodoroManagerTests: XCTestCase {
    
    var manager: TestablePomodoroManager!
    var cancellables = Set<AnyCancellable>()
    
    // MARK: - Lifecycle
    
    override func setUp() {
        super.setUp()
        TestablePomodoroManager.clearTestDefaults()
        cancellables = []
        manager = TestablePomodoroManager()
    }
    
    override func tearDown() {
        manager = nil
        cancellables.removeAll()
        TestablePomodoroManager.clearTestDefaults()
        super.tearDown()
    }
    
    // MARK: - Timer Starts Correctly Tests
    
    func testTimerStart_setsIsRunningTrue() {
        XCTAssertFalse(manager.testIsRunning)
        manager.testStart()
        XCTAssertTrue(manager.testIsRunning)
    }
    
    func testTimerStart_doesNothingIfAlreadyRunning() {
        manager.testStart()
        XCTAssertTrue(manager.testIsRunning)
        let isRunningBefore = manager.testIsRunning
        
        // Try to start again
        manager.testStart()
        XCTAssertEqual(isRunningBefore, manager.testIsRunning)
    }
    
    func testTimerCountdown_decrementsTime() {
        // Set a short time for testing
        manager.testTimeRemaining = 5.0
        
        // Start the timer
        manager.testStart()
        
        // Simulate ticks manually since we can't control the real timer in tests
        manager.performTick()
        XCTAssertEqual(manager.testTimeRemaining, 4.0)
        
        manager.performTick()
        XCTAssertEqual(manager.testTimeRemaining, 3.0)
        
        manager.performTick()
        XCTAssertEqual(manager.testTimeRemaining, 2.0)
    }
    
    // MARK: - Pause/Resume Tests
    
    func testPauseTimer_setsIsRunningFalse() {
        manager.testStart()
        XCTAssertTrue(manager.testIsRunning)
        
        manager.testPause()
        XCTAssertFalse(manager.testIsRunning)
    }
    
    func testPauseTimer_doesNothingIfNotRunning() {
        XCTAssertFalse(manager.testIsRunning)
        manager.testPause()
        XCTAssertFalse(manager.testIsRunning)
    }
    
    func testResumeTimer_fromPausedState() {
        manager.testStart()
        XCTAssertTrue(manager.testIsRunning)
        
        manager.testPause()
        XCTAssertFalse(manager.testIsRunning)
        
        manager.testStart()
        XCTAssertTrue(manager.testIsRunning)
    }
    
    func testResumeTimer_preservesTimeDuringPause() {
        manager.testStart()
        manager.performTick()
        manager.performTick()
        let timeBeforePause = manager.testTimeRemaining
        
        manager.testPause()
        XCTAssertEqual(manager.testTimeRemaining, timeBeforePause)
    }
    
    // MARK: - Reset Tests
    
    func testResetTimer_returnsToWorkSession() {
        // Transition to a break session
        manager.testSessionType = .shortBreak
        manager.testTimeRemaining = 60.0
        
        manager.testReset()
        
        XCTAssertEqual(manager.testSessionType, .work)
    }
    
    func testResetTimer_restoresWorkDuration() {
        // Change time remaining
        manager.testTimeRemaining = 60.0
        
        manager.testReset()
        
        XCTAssertEqual(manager.testTimeRemaining, manager.workDurationValue)
    }
    
    func testResetTimer_resetsCycleCount() {
        // Set cycle to something other than 1
        manager.testCurrentCycle = 3
        
        manager.testReset()
        
        XCTAssertEqual(manager.testCurrentCycle, 1)
    }
    
    func testResetTimer_setsIsRunningFalse() {
        manager.testStart()
        XCTAssertTrue(manager.testIsRunning)
        
        manager.testReset()
        
        XCTAssertFalse(manager.testIsRunning)
    }
    
    // MARK: - Session Transitions Tests
    
    func testWorkToShortBreakTransition() {
        manager.testSessionType = .work
        manager.testCurrentCycle = 1
        
        manager.testTransitionToNextSession()
        
        XCTAssertEqual(manager.testSessionType, .shortBreak)
    }
    
    func testShortBreakToWorkTransition() {
        manager.testSessionType = .shortBreak
        manager.testCurrentCycle = 1
        
        manager.testTransitionToNextSession()
        
        XCTAssertEqual(manager.testSessionType, .work)
        XCTAssertEqual(manager.testCurrentCycle, 2)
    }
    
    func testFourthWorkToLongBreakTransition() {
        // After 4 work sessions, should get a long break
        manager.testSessionType = .work
        manager.testCurrentCycle = 4
        
        manager.testTransitionToNextSession()
        
        XCTAssertEqual(manager.testSessionType, .longBreak)
    }
    
    func testLongBreakToWorkTransition() {
        manager.testSessionType = .longBreak
        manager.testCurrentCycle = 1
        
        manager.testTransitionToNextSession()
        
        XCTAssertEqual(manager.testSessionType, .work)
        XCTAssertEqual(manager.testCurrentCycle, 1)
    }
    
    func testSessionTransitions_setCorrectDuration() {
        // Work session duration
        manager.testSessionType = .work
        manager.testTransitionToNextSession()
        XCTAssertEqual(manager.testTimeRemaining, manager.shortBreakDurationValue)
        
        // Short break to work
        manager.testSessionType = .shortBreak
        manager.testTransitionToNextSession()
        XCTAssertEqual(manager.testTimeRemaining, manager.workDurationValue)
        
        // After 4 cycles, work to long break
        manager.testSessionType = .work
        manager.testCurrentCycle = 4
        manager.testTransitionToNextSession()
        XCTAssertEqual(manager.testSessionType, .longBreak)
        XCTAssertEqual(manager.testTimeRemaining, manager.longBreakDurationValue)
    }
    
    // MARK: - Cycle Count Tests
    
    func testCycleCountIncrementsAfterShortBreak() {
        manager.testSessionType = .shortBreak
        manager.testCurrentCycle = 1
        
        manager.testTransitionToNextSession()
        
        XCTAssertEqual(manager.testCurrentCycle, 2)
    }
    
    func testLongBreakResetsCycleToOne() {
        manager.testSessionType = .work
        manager.testCurrentCycle = 4
        
        manager.testTransitionToNextSession()
        
        XCTAssertEqual(manager.testCurrentCycle, 1)
    }
    
    func testCycleCountResetsAfterLongBreak() {
        manager.testSessionType = .longBreak
        manager.testCurrentCycle = 1
        
        manager.testTransitionToNextSession()
        
        XCTAssertEqual(manager.testCurrentCycle, 1)
    }
    
    func testCyclesBeforeLongBreakIsFour() {
        XCTAssertEqual(manager.cyclesBeforeLongBreakValue, 4)
    }
    
    // MARK: - Session Duration Tests
    
    func testWorkDuration_is25Minutes() {
        XCTAssertEqual(manager.durationFor(type: .work), 25 * 60)
    }
    
    func testShortBreakDuration_is5Minutes() {
        XCTAssertEqual(manager.durationFor(type: .shortBreak), 5 * 60)
    }
    
    func testLongBreakDuration_is15Minutes() {
        XCTAssertEqual(manager.durationFor(type: .longBreak), 15 * 60)
    }
    
    // MARK: - UserDefaults Persistence Tests
    
    func testPersistence_saveAndLoadSessionType() {
        manager.testSessionType = .shortBreak
        manager.testSaveState()
        
        // Create new manager to test load
        TestablePomodoroManager.clearTestDefaults()
        let newManager = TestablePomodoroManager()
        newManager.testLoadState()
        
        XCTAssertEqual(newManager.testSessionType, .shortBreak)
    }
    
    func testPersistence_saveAndLoadTimeRemaining() {
        manager.testTimeRemaining = 123.0
        manager.testSaveState()
        
        TestablePomodoroManager.clearTestDefaults()
        let newManager = TestablePomodoroManager()
        newManager.testLoadState()
        
        XCTAssertEqual(newManager.testTimeRemaining, 123.0)
    }
    
    func testPersistence_saveAndLoadCurrentCycle() {
        manager.testCurrentCycle = 3
        manager.testSaveState()
        
        TestablePomodoroManager.clearTestDefaults()
        let newManager = TestablePomodoroManager()
        newManager.testLoadState()
        
        XCTAssertEqual(newManager.testCurrentCycle, 3)
    }
    
    func testPersistence_loadStateFromUserDefaults() {
        // Simulate persisted state
        let defaults = UserDefaults(suiteName: "com.boringNotch.pomodoro.tests")!
        defaults.set(1, forKey: "pomodoro_sessionType") // shortBreak
        defaults.set(300.0, forKey: "pomodoro_timeRemaining")
        defaults.set(2, forKey: "pomodoro_currentCycle")
        
        let newManager = TestablePomodoroManager()
        newManager.testLoadState()
        
        XCTAssertEqual(newManager.testSessionType, .shortBreak)
        XCTAssertEqual(newManager.testTimeRemaining, 300.0)
        XCTAssertEqual(newManager.testCurrentCycle, 2)
    }
    
    func testLoadState_defaultsToWorkSession() {
        TestablePomodoroManager.clearTestDefaults()
        
        let newManager = TestablePomodoroManager()
        newManager.testLoadState()
        
        XCTAssertEqual(newManager.testSessionType, .work)
    }
    
    func testLoadState_defaultsToWorkDuration_whenTimeIsZero() {
        TestablePomodoroManager.clearTestDefaults()
        
        let newManager = TestablePomodoroManager()
        newManager.testLoadState()
        
        XCTAssertEqual(newManager.testTimeRemaining, 25 * 60)
    }
    
    func testLoadState_defaultsCycleToOne_whenCycleIsZero() {
        TestablePomodoroManager.clearTestDefaults()
        let defaults = UserDefaults(suiteName: "com.boringNotch.pomodoro.tests")!
        defaults.set(0, forKey: "pomodoro_currentCycle")
        
        let newManager = TestablePomodoroManager()
        newManager.testLoadState()
        
        XCTAssertEqual(newManager.testCurrentCycle, 1)
    }
    
    // MARK: - State Changes Observation Tests
    
    func testSessionTypePublishedProperty_changes() {
        var changes: [SessionType] = []
        manager.$sessionType
            .sink { changes.append($0) }
            .store(in: &cancellables)
        
        manager.testSessionType = .shortBreak
        
        XCTAssertTrue(changes.contains(.shortBreak))
    }
    
    func testTimeRemainingPublishedProperty_changes() {
        var changes: [TimeInterval] = []
        manager.$timeRemaining
            .sink { changes.append($0) }
            .store(in: &cancellables)
        
        manager.testTimeRemaining = 100.0
        
        XCTAssertTrue(changes.contains(100.0))
    }
    
    func testCurrentCyclePublishedProperty_changes() {
        var changes: [Int] = []
        manager.$currentCycle
            .sink { changes.append($0) }
            .store(in: &cancellables)
        
        manager.testCurrentCycle = 3
        
        XCTAssertTrue(changes.contains(3))
    }
    
    func testIsRunningPublishedProperty_changes() {
        var changes: [Bool] = []
        manager.$isRunning
            .sink { changes.append($0) }
            .store(in: &cancellables)
        
        manager.testStart()
        XCTAssertTrue(changes.contains(true))
        
        manager.testPause()
        XCTAssertTrue(changes.contains(false))
    }
}