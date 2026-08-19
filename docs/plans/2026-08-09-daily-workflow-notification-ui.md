# Daily Workflow Notification UI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Notify the user when morning planning or evening review is due without opening the notch, open the workflow only after hover or click, and polish session completion and reminder interactions.

**Architecture:** `DailyPlanningManager` will separate a due-but-unopened `pendingSession` from the currently displayed `activeSession`. `ContentView` will render a compact closed-notch prompt for the pending session and activate it through the existing hover/tap path. Reusable SwiftUI components in `DailyPlanningView.swift` will provide the app-themed session action and the animated reminder control.

**Tech Stack:** Swift 6, SwiftUI, EventKit, XCTest, macOS 14

---

### Task 1: Introduce pending presentation state

**Files:**
- Modify: `boringNotch/features/DailyPlanning/DailyPlanningManager.swift`

**Step 1: Verify the current automatic presentation behavior**

Run:

```bash
rg -n "activeSession|dailyWorkflowNeedsPresentation|evaluateNow" boringNotch/features/DailyPlanning/DailyPlanningManager.swift
```

Expected: `evaluateNow` creates `activeSession` and immediately posts `dailyWorkflowNeedsPresentation`.

**Step 2: Add pending state**

Add a published pending session and expose a read-only predicate:

```swift
@Published private(set) var pendingSession: DailyWorkflowSession?

var isAwaitingPresentation: Bool { pendingSession != nil }
```

Change scheduling so a due workflow is stored in `pendingSession` without loading reminders or posting the presentation notification.

**Step 3: Add explicit activation**

Add a method that returns `true` only when a pending workflow was activated:

```swift
@discardableResult
func activatePendingSession() -> Bool {
    guard activeSession == nil, let session = pendingSession else { return false }
    pendingSession = nil
    activeSession = session
    contentState = .loading
    NotificationCenter.default.post(name: .dailyWorkflowNeedsPresentation, object: nil)
    Task { await reloadActiveSession() }
    return true
}
```

Ensure repeated evaluation leaves a valid pending session waiting and clears it if the corresponding workflow becomes disabled or moves back into the future.

**Step 4: Build to catch actor or publication errors**

Run the Debug `xcodebuild` command used for this feature.

Expected: `BUILD SUCCEEDED`.

### Task 2: Add a closed-notch workflow prompt

**Files:**
- Modify: `boringNotch/ContentView.swift`
- Modify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift`

**Step 1: Render the pending session before other closed-notch activities**

In `NotchLayout`, give a pending workflow priority over battery, OSD, music, and face content:

```swift
if let session = dailyPlanningManager.pendingSession, vm.notchState == .closed {
    DailyWorkflowNotificationView(session: session, notchWidth: vm.closedNotchSize.width)
}
```

Increase `computedChinWidth` for the prompt so menu-bar hit testing follows its visible width.

**Step 2: Activate on intentional hover**

Allow the pending prompt to use the existing minimum-hover delay even when “Open notch on hover” is disabled. Route both hover and click through `doOpen()`, which calls `activatePendingSession()` before opening.

Expected: reaching a configured time only changes the closed-notch prompt; hovering or clicking opens the daily workflow.

**Step 3: Implement the reference-inspired animation**

Create `DailyWorkflowNotificationView` with:

- `bell.fill` using a short keyframed ring around its top anchor;
- a small accent dot with a repeating expanding/fading ring;
- “Morning planning begins!” or “Evening review begins!”;
- dark materials and `Color.effectiveAccent` so it matches the existing theme.

**Step 4: Manually verify interruption behavior**

Set a workflow time to the current minute.

Expected: the workflow does not open automatically; the compact prompt appears and opens only after hover/click.

### Task 3: Replace the generic finish button

**Files:**
- Modify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift`

**Step 1: Add workflow-specific copy**

Use:

```swift
sessionKind == .eveningReview ? "Wrap Up My Day" : "Start My Day"
```

**Step 2: Add an app-themed action style**

Create a capsule button using `Color.effectiveAccent`, a subtle accent border/glow, an arrow icon, hover lift, and pressed scaling. Keep the existing finish action and fade-before-close timing unchanged.

**Step 3: Verify accessibility**

Ensure the full capsule is the hit target and its accessibility label matches the visible action copy.

### Task 4: Animate reminder completion

**Files:**
- Modify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift`

**Step 1: Extract a stateful reminder row**

Replace the function-only row with `DailyReminderRow`, storing the visual completion state long enough to finish the animation before the evening columns re-sort the item.

**Step 2: Implement the reference interaction**

Create `DailyReminderCompletionButton` where:

- an incomplete horizontal dash collapses;
- two trimmed strokes draw the checkmark;
- six accent particles expand and fade after completion;
- unchecking reverses to the dash without particles.

Animate the title a few points sideways while drawing/removing its strike-through. Start the visual change immediately, then save through `DailyPlanningManager` after the short transition.

**Step 3: Preserve optimistic behavior**

Disable only the reminder currently transitioning or saving. Keep EventKit reload silent and allow external EventKit updates to synchronize the row.

### Task 5: Verify and relaunch

**Files:**
- Test: `boringNotchTests/DailyPlanningCoreTests.swift`
- Verify: all modified Swift files

**Step 1: Run package tests**

Run:

```bash
swift test --disable-sandbox
```

Expected: all daily planning core tests pass.

**Step 2: Check formatting damage**

Run:

```bash
git diff --check
```

Expected: no output.

**Step 3: Follow the requested Debug lifecycle**

Close the running Boring Notch Debug app, delete the `dev.codex.boringnotch.dailyplanning` preferences domain, rebuild to `/tmp/boring-notch-preserved-settings-build`, and open the rebuilt app.

Expected: `BUILD SUCCEEDED`, the Debug app opens at default/onboarding settings, and no Apple Reminders data is erased.
