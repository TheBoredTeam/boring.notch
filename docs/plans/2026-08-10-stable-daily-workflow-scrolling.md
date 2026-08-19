# Stable Daily Workflow Scrolling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep the notch window visually stable while users scroll morning-planning and evening-review reminder lists.

**Architecture:** The daily workflow remains inside its existing fixed-size notch window. The global upward-close gesture will be disabled only while the daily-planning coordinator view is active, allowing the nested SwiftUI `ScrollView` to consume scroll events without changing the notch-wide gesture progress.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Package Manager, Xcode

---

### Task 1: Confirm the resize path

**Files:**
- Inspect: `boringNotch/features/DailyPlanning/DailyPlanningView.swift`
- Inspect: `boringNotch/extensions/PanGesture.swift`
- Inspect: `boringNotch/ContentView.swift`
- Inspect: `boringNotch/sizing/matters.swift`

**Step 1:** Trace reminder-list scroll events through the notch-wide pan gesture.

**Step 2:** Confirm that `gestureProgress` scales the root notch even though the `NSWindow` frame remains fixed.

**Step 3:** Choose the narrowest guard that remains active through the daily workflow's finish transition.

### Task 2: Prevent daily workflow scrolls from scaling the notch

**Files:**
- Modify: `boringNotch/ContentView.swift`

**Step 1:** Add `coordinator.currentView != .dailyPlanning` to `handleUpGesture`'s entry guard.

**Step 2:** Review the diff and confirm that no daily-workflow layout or shared gesture implementation was changed.

### Task 3: Verify behavior

**Files:**
- Test: `Tests/`
- Build: `boringNotch.xcodeproj`

**Step 1:** Run `swift test --disable-sandbox`.

**Step 2:** Quit the running Debug app and erase `dev.codex.boringnotch.dailyplanning` preferences.

**Step 3:** Build the Debug app with the dedicated bundle identifier and reopen it.

**Step 4:** Trigger morning planning and scroll in both directions, including a large upward flick and momentum at list edges; confirm the content moves while the notch silhouette stays fixed and open.

**Step 5:** Repeat for the evening review's completed and incomplete sections when test data permits.

**Step 6:** Confirm the finish action still closes the workflow and the normal Home upward-close gesture still works.

**Step 7:** Erase Debug preferences again and leave the clean Debug app open.

### Task 4: Publish the focused change

**Files:**
- Stage: `boringNotch/ContentView.swift`
- Exclude: `docs/`
- Exclude: `sketches/`

**Step 1:** Review status and stage only `boringNotch/ContentView.swift`.

**Step 2:** Commit as `Keep daily workflow window stable while scrolling`.

**Step 3:** Push `feature/daily-planning-review` to the fork.

**Step 4:** Confirm PR #1438 points at the pushed head and inspect checks without changing its title, body, description, or draft state.
