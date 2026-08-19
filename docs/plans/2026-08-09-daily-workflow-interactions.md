# Daily Workflow Interactions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let people complete a Reminder directly from the daily planning/review notch and remove the daily UI before the notch closes after finishing a session.

**Architecture:** Keep EventKit writes in `DailyPlanningManager`, which already owns the session and can reload the fetched reminders. Give `DailyPlanningView` a short finishing state that hides its content before it asks the existing notch coordinator to close. Reuse the Calendar’s `ReminderToggle` visual behaviour through an equivalent SwiftUI binding in the daily workflow view.

**Tech Stack:** Swift, SwiftUI, EventKit, XCTest, Xcode.

---

### Task 1: Add completion and finishing-state behaviour to the daily workflow manager

**Files:**

- Modify: `boringNotch/features/DailyPlanning/DailyPlanningManager.swift`
- Test: `boringNotchTests/DailyPlanningCoreTests.swift`

**Step 1: Write the failing test**

Add a focused manager/core test seam for the state transition that is safe to run without EventKit: a finishing state must block duplicate Finish taps, and a successful reminder mutation must refresh the active session’s content.

**Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox`

Expected: the new state-transition expectation fails because the manager has neither a finishing state nor a reminder-completion API.

**Step 3: Write minimal implementation**

Add published state such as `isFinishingSession`. Add an async `setReminderCompleted(reminderID:completed:)` method that calls the existing `CalendarServiceProviding.setReminderCompleted`, then reloads the active session so the item changes column/state. Make `finishActiveSession` first set the finishing state; after the view’s brief clear-content delay, persist completion and post `.dailyWorkflowDidFinish`. Reset the finishing state if persistence fails.

**Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox`

Expected: all daily-planning core tests pass.

**Step 5: Commit**

```bash
git add boringNotch/features/DailyPlanning/DailyPlanningManager.swift boringNotchTests/DailyPlanningCoreTests.swift
git commit -m "feat: support reminder completion in daily workflow"
```

### Task 2: Make reminder completion circles actionable in daily planning and review

**Files:**

- Modify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift`
- Reference: `boringNotch/components/Calendar/BoringCalendar.swift:665-679`

**Step 1: Write the failing test**

Add a view-level/manual acceptance criterion: clicking an incomplete row’s circle invokes `DailyPlanningManager.setReminderCompleted` with `true`; clicking a completed row’s circle invokes it with `false`.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -quiet -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`

Expected: current build succeeds but manual behaviour fails because the circle is only an `Image`, not a control.

**Step 3: Write minimal implementation**

Replace the decorative image in `reminderRow` with a `Button` or the project’s `ReminderToggle`, binding its value to `item.isCompleted`. In its action, start a `Task` that awaits the manager mutation. Disable only that row’s control while its identifier is being saved, preserving the rest of the planning/review UI. Keep the existing completed colour and strikethrough, so a reloaded evening review moves the item between Still open and Completed.

**Step 4: Run test to verify it passes**

Run: `xcodebuild -quiet -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`

Expected: build succeeds with no new errors.

**Step 5: Commit**

```bash
git add boringNotch/features/DailyPlanning/DailyPlanningView.swift
git commit -m "feat: make daily reminder status interactive"
```

### Task 3: Clear the daily workflow UI before the notch close animation

**Files:**

- Modify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift`
- Modify: `boringNotch/features/DailyPlanning/DailyPlanningManager.swift`

**Step 1: Write the failing test**

Define the manual acceptance test: after pressing Finish Planning or Finish Review, the title, reminder rows, and Finish button disappear immediately; only after a short fixed delay does the existing notch close animation start.

**Step 2: Run test to verify it fails**

Run: `xcodebuild -quiet -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`

Expected: build succeeds but manual test fails because `finishActiveSession()` immediately posts the close notification while the view still contains its text and rows.

**Step 3: Write minimal implementation**

When Finish is tapped, set the manager’s finishing state. Have `DailyPlanningView` render an empty, transparent layout while that state is true and use a short SwiftUI task/animation completion delay (about 0.15–0.25 seconds) before calling a manager method that finalizes the session. Keep the session active until finalization, so Escape and automatic close remain blocked. Disable the Finish button during the transition.

**Step 4: Run test to verify it passes**

Run: `xcodebuild -quiet -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`

Expected: build succeeds. In the running app, confirm that the empty notch is visible briefly before its close animation for both morning and evening sessions.

**Step 5: Commit**

```bash
git add boringNotch/features/DailyPlanning/DailyPlanningView.swift boringNotch/features/DailyPlanning/DailyPlanningManager.swift
git commit -m "fix: clear daily workflow before closing notch"
```

### Task 4: Final regression verification

**Files:**

- Verify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift`
- Verify: `boringNotch/features/DailyPlanning/DailyPlanningManager.swift`

**Step 1: Run focused automated checks**

Run: `swift test --disable-sandbox`

Expected: all tests pass.

**Step 2: Build the macOS app**

Run: `xcodebuild -quiet -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`

Expected: Debug app builds successfully with no new warnings or errors introduced by this feature.

**Step 3: Run manual acceptance checks**

1. Start an active morning planning session containing an incomplete native Apple Reminder; click its circle and confirm it becomes completed without closing the notch.
2. Start an evening review; click a Still open item’s circle and confirm it moves to Completed after reload. Click it again and confirm it returns to Still open.
3. Press Finish Planning and Finish Review separately; in each case confirm all daily-workflow text disappears before the notch begins closing, and that Escape cannot dismiss it during the brief transition.

**Step 4: Check the patch for formatting errors**

Run: `git diff --check`

Expected: no output and exit code 0.
