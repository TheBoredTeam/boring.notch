import XCTest

@testable import DailyPlanningCore

final class DailyPlanningCoreTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func date(
    year: Int = 2026,
    month: Int = 8,
    day: Int = 8,
    hour: Int,
    minute: Int = 0
  ) -> Date {
    calendar.date(
      from: DateComponents(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
      ))!
  }

  func testMorningSessionBecomesDueAfterConfiguredTime() {
    let preferences = DailyWorkflowPreferences(
      morningPlanningEnabled: true,
      morningPlanningMinutes: 8 * 60,
      eveningReviewEnabled: false,
      eveningReviewMinutes: 20 * 60
    )

    XCTAssertNil(
      DailyWorkflowSchedule.dueWorkflow(
        at: date(hour: 7, minute: 59),
        preferences: preferences,
        completionState: .init(),
        calendar: calendar
      ))
    XCTAssertEqual(
      DailyWorkflowSchedule.dueWorkflow(
        at: date(hour: 8),
        preferences: preferences,
        completionState: .init(),
        calendar: calendar
      ), .morningPlanning)
  }

  func testReminderSectionsFilterToSessionDayAndSeparateCompletion() {
    let items = [
      DailyReminderItem(
        id: "open", title: "Open", dueDate: date(hour: 9), isCompleted: false,
        listTitle: "Work"),
      DailyReminderItem(
        id: "done", title: "Done", dueDate: date(hour: 10), isCompleted: true,
        listTitle: "Home"),
      DailyReminderItem(
        id: "tomorrow", title: "Tomorrow", dueDate: date(day: 9, hour: 9),
        isCompleted: false,
        listTitle: "Work"),
    ]

    let sections = DailyReminderSections(
      items: items, sessionDate: date(hour: 12), calendar: calendar)

    XCTAssertEqual(sections.all.map(\.id), ["open", "done"])
    XCTAssertEqual(sections.incomplete.map(\.id), ["open"])
    XCTAssertEqual(sections.completed.map(\.id), ["done"])
    XCTAssertEqual(sections.all.map(\.listTitle), ["Work", "Home"])
    XCTAssertEqual(sections.incomplete.map(\.listTitle), ["Work"])
    XCTAssertEqual(sections.completed.map(\.listTitle), ["Home"])
  }

  func testCompletedSessionIsSuppressedForThatDay() {
    let preferences = DailyWorkflowPreferences(
      morningPlanningEnabled: true,
      morningPlanningMinutes: 8 * 60,
      eveningReviewEnabled: false,
      eveningReviewMinutes: 20 * 60
    )
    var completion = DailyWorkflowCompletionState()
    completion.markCompleted(.morningPlanning, on: date(hour: 9), calendar: calendar)

    XCTAssertNil(
      DailyWorkflowSchedule.dueWorkflow(
        at: date(hour: 10),
        preferences: preferences,
        completionState: completion,
        calendar: calendar
      ))
    XCTAssertEqual(
      DailyWorkflowSchedule.dueWorkflow(
        at: date(day: 9, hour: 10),
        preferences: preferences,
        completionState: completion,
        calendar: calendar
      ), .morningPlanning)
  }

  func testMorningTakesPriorityWhenBothSessionsAreOverdue() {
    let preferences = DailyWorkflowPreferences(
      morningPlanningEnabled: true,
      morningPlanningMinutes: 8 * 60,
      eveningReviewEnabled: true,
      eveningReviewMinutes: 20 * 60
    )

    XCTAssertEqual(
      DailyWorkflowSchedule.dueWorkflow(
        at: date(hour: 21),
        preferences: preferences,
        completionState: .init(),
        calendar: calendar
      ), .morningPlanning)
  }

  func testChangingTimeChangesNextEvaluation() {
    let early = DailyWorkflowPreferences(
      morningPlanningEnabled: true,
      morningPlanningMinutes: 8 * 60,
      eveningReviewEnabled: false,
      eveningReviewMinutes: 20 * 60
    )
    let later = DailyWorkflowPreferences(
      morningPlanningEnabled: true,
      morningPlanningMinutes: 9 * 60,
      eveningReviewEnabled: false,
      eveningReviewMinutes: 20 * 60
    )

    XCTAssertEqual(
      DailyWorkflowSchedule.nextEvaluation(
        after: date(hour: 7),
        preferences: early,
        completionState: .init(),
        calendar: calendar
      ), date(hour: 8))
    XCTAssertEqual(
      DailyWorkflowSchedule.nextEvaluation(
        after: date(hour: 7),
        preferences: later,
        completionState: .init(),
        calendar: calendar
      ), date(hour: 9))
  }

  func testChangingEveningTimeChangesNextEvaluation() {
    var completion = DailyWorkflowCompletionState()
    completion.markCompleted(.morningPlanning, on: date(hour: 12), calendar: calendar)

    let early = DailyWorkflowPreferences(
      morningPlanningEnabled: true,
      morningPlanningMinutes: 8 * 60,
      eveningReviewEnabled: true,
      eveningReviewMinutes: 20 * 60
    )
    let later = DailyWorkflowPreferences(
      morningPlanningEnabled: true,
      morningPlanningMinutes: 8 * 60,
      eveningReviewEnabled: true,
      eveningReviewMinutes: 21 * 60
    )

    XCTAssertEqual(
      DailyWorkflowSchedule.nextEvaluation(
        after: date(hour: 19),
        preferences: early,
        completionState: completion,
        calendar: calendar
      ), date(hour: 20))
    XCTAssertEqual(
      DailyWorkflowSchedule.nextEvaluation(
        after: date(hour: 19),
        preferences: later,
        completionState: completion,
        calendar: calendar
      ), date(hour: 21))
  }

  func testMovingPendingTriggerIntoPastMakesSessionDueImmediately() {
    let future = DailyWorkflowPreferences(
      morningPlanningEnabled: true,
      morningPlanningMinutes: 10 * 60,
      eveningReviewEnabled: false,
      eveningReviewMinutes: 20 * 60
    )
    let movedEarlier = DailyWorkflowPreferences(
      morningPlanningEnabled: true,
      morningPlanningMinutes: 8 * 60,
      eveningReviewEnabled: false,
      eveningReviewMinutes: 20 * 60
    )

    XCTAssertNil(
      DailyWorkflowSchedule.dueWorkflow(
        at: date(hour: 9),
        preferences: future,
        completionState: .init(),
        calendar: calendar
      ))
    XCTAssertEqual(
      DailyWorkflowSchedule.dueWorkflow(
        at: date(hour: 9),
        preferences: movedEarlier,
        completionState: .init(),
        calendar: calendar
      ), .morningPlanning)
  }

  func testPreferencesAndCompletionPersistAcrossStoreInstances() throws {
    let suiteName = "DailyPlanningCoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let preferences = DailyWorkflowPreferences(
      morningPlanningEnabled: true,
      morningPlanningMinutes: 7 * 60 + 30,
      eveningReviewEnabled: true,
      eveningReviewMinutes: 21 * 60
    )
    var completion = DailyWorkflowCompletionState()
    completion.markCompleted(.eveningReview, on: date(hour: 22), calendar: calendar)

    let writer = DailyWorkflowPreferencesStore(defaults: defaults)
    try writer.savePreferences(preferences)
    try writer.saveCompletionState(completion)

    let reader = DailyWorkflowPreferencesStore(defaults: defaults)
    XCTAssertEqual(reader.loadPreferences(), preferences)
    XCTAssertEqual(reader.loadCompletionState(), completion)
  }

  func testMissedMorningTriggerIsRecoveredAfterStoreReload() throws {
    let suiteName = "DailyPlanningCoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let writer = DailyWorkflowPreferencesStore(defaults: defaults)
    try writer.savePreferences(
      DailyWorkflowPreferences(
        morningPlanningEnabled: true,
        morningPlanningMinutes: 8 * 60,
        eveningReviewEnabled: false,
        eveningReviewMinutes: 20 * 60
      ))

    let relaunchedStore = DailyWorkflowPreferencesStore(defaults: defaults)
    XCTAssertEqual(
      DailyWorkflowSchedule.dueWorkflow(
        at: date(hour: 10),
        preferences: relaunchedStore.loadPreferences(),
        completionState: relaunchedStore.loadCompletionState(),
        calendar: calendar
      ), .morningPlanning)
  }

  func testEveningBecomesDueAfterOverdueMorningIsCompleted() {
    let preferences = DailyWorkflowPreferences(
      morningPlanningEnabled: true,
      morningPlanningMinutes: 8 * 60,
      eveningReviewEnabled: true,
      eveningReviewMinutes: 20 * 60
    )
    var completion = DailyWorkflowCompletionState()
    completion.markCompleted(.morningPlanning, on: date(hour: 21), calendar: calendar)

    XCTAssertEqual(
      DailyWorkflowSchedule.dueWorkflow(
        at: date(hour: 21),
        preferences: preferences,
        completionState: completion,
        calendar: calendar
      ), .eveningReview)
  }

  func testDisabledSessionsNeverBecomeDue() {
    XCTAssertNil(
      DailyWorkflowSchedule.dueWorkflow(
        at: date(hour: 23),
        preferences: .default,
        completionState: .init(),
        calendar: calendar
      ))
    XCTAssertNil(
      DailyWorkflowSchedule.nextEvaluation(
        after: date(hour: 23),
        preferences: .default,
        completionState: .init(),
        calendar: calendar
      ))
  }

  func testPendingPromptShowsWhenNoTransientIndicatorIsVisible() {
    XCTAssertTrue(
      DailyWorkflowPresentationPolicy.shouldShowPendingPrompt(
        hasPendingSession: true,
        isNotchClosed: true,
        isClosedOSDVisible: false,
        isPowerNotificationVisible: false,
        isGreetingAnimationVisible: false
      ))
  }

  func testOSDAndPowerNotificationsTakePriorityOverPendingPrompt() {
    XCTAssertFalse(
      DailyWorkflowPresentationPolicy.shouldShowPendingPrompt(
        hasPendingSession: true,
        isNotchClosed: true,
        isClosedOSDVisible: true,
        isPowerNotificationVisible: false,
        isGreetingAnimationVisible: false
      ))
    XCTAssertFalse(
      DailyWorkflowPresentationPolicy.shouldShowPendingPrompt(
        hasPendingSession: true,
        isNotchClosed: true,
        isClosedOSDVisible: false,
        isPowerNotificationVisible: true,
        isGreetingAnimationVisible: false
      ))
  }

  func testGreetingAnimationTakesPriorityOverPendingPrompt() {
    XCTAssertFalse(
      DailyWorkflowPresentationPolicy.shouldShowPendingPrompt(
        hasPendingSession: true,
        isNotchClosed: true,
        isClosedOSDVisible: false,
        isPowerNotificationVisible: false,
        isGreetingAnimationVisible: true
      ))
  }
}
