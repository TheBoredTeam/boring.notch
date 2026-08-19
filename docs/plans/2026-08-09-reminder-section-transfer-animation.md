# Reminder Section Transfer Animation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Present reminders as plain icon-and-text rows, reproduce the circular stroke-to-check animation, keep the strike-through visible, and stage evening reminders cleanly between incomplete and completed sections.

**Architecture:** `DailyPlanningManager` will own a small per-reminder transition state so it survives the outgoing SwiftUI row being destroyed and the incoming row being created in another `ForEach`. EventKit change notifications will be ignored while local edits are active and reconciled once after all edits finish. The row renders completion and visibility entirely from the manager state.

**Tech Stack:** Swift 6, SwiftUI, EventKit, XCTest, macOS 14

---

### Task 1: Add manager-owned reminder transition state

**Files:**
- Modify: `boringNotch/features/DailyPlanning/DailyPlanningManager.swift`

**Step 1: Define transition phases**

Add:

```swift
enum DailyReminderTransitionPhase: Equatable {
    case animatingControl
    case hidden
    case revealed
}

struct DailyReminderTransition: Equatable {
    let targetCompletion: Bool
    var phase: DailyReminderTransitionPhase
}
```

Publish a dictionary keyed by reminder ID.

**Step 2: Prevent premature EventKit reloads**

In the `.EKEventStoreChanged` observer, reload only when an active session exists and `updatingReminderIDs` is empty.

Expected: the save-generated notification cannot move a row during its control animation.

**Step 3: Stage the evening transfer**

At the start of `setReminderCompleted`, publish the target with `.animatingControl` and begin saving immediately. Then:

1. wait 420 ms for circle/check and strike animation;
2. animate the phase to `.hidden` over 180 ms;
3. update local section membership without animation;
4. animate the phase to `.revealed` over 180 ms;
5. remove transition state after the reveal;
6. remove the in-flight ID and reload once only when no other edits remain.

Capture the active session ID and abort UI phases cleanly if that session finishes. Handle `Task.sleep` cancellation explicitly and always clear transient state.

### Task 2: Replace the checkbox animation and remove row cards

**Files:**
- Modify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift`

**Step 1: Remove the row background**

Delete the rounded translucent background. Keep compact vertical padding, the completion control, title, and reminder-list label.

**Step 2: Implement the circular reference animation**

Build an 18-point control from two strokes:

- a grey circular `Shape.trim` erases clockwise over 300 ms when completing;
- the accent checkmark draws over 200 ms after a 150 ms delay;
- unchecking reverses the order;
- hovering tints the circle with `Color.effectiveAccent`.

Expected: the animation mirrors the supplied WhiteNervosa reference without copying CSS into the native app.

**Step 3: Make strike-through explicitly animatable**

Replace the overlay capsule with a `Shape` whose `animatableData` is its horizontal progress. Draw from leading to trailing on completion and retract on uncompletion while shifting the title slightly.

### Task 3: Render staged visibility across evening sections

**Files:**
- Modify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift`

**Step 1: Derive row state from the manager**

Use `reminderTransitions[item.id]?.targetCompletion` for the displayed checkbox/strike state and make `.hidden` rows opacity zero.

**Step 2: Trigger the manager sequence**

Call `setReminderCompleted` with staged section transfer enabled only for `.eveningReview`; morning planning keeps the row in place after its control animation.

Expected evening behavior in either direction: animate control and strike, fade out from the current section, move while invisible, then fade into the destination section.

### Task 4: Verify and relaunch

**Files:**
- Verify: `boringNotch/features/DailyPlanning/DailyPlanningManager.swift`
- Verify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift`

**Step 1:** Run `git diff --check`; expect no output.

**Step 2:** Run `swift test --disable-sandbox`; expect all daily-planning tests to pass.

**Step 3:** Close the Debug app, erase only `dev.codex.boringnotch.dailyplanning` preferences, and run the full Debug `xcodebuild`; expect success.

**Step 4:** Reopen `/tmp/boring-notch-preserved-settings-build/Build/Products/Debug/boringNotch.app`; expect reset onboarding and no change to Apple Reminders data.
