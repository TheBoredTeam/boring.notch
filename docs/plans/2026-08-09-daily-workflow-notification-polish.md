# Daily Workflow Notification Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn the pending daily-workflow alert into a single rounded notch notification with clearer visual order and friendlier copy.

**Architecture:** Keep the existing pending-session and hover activation behavior unchanged. Restructure only `DailyWorkflowNotificationView` so the animated bell, message, and pulsing green status dot share one horizontal group, then provide larger closed-notch corner radii while that group is visible.

**Tech Stack:** Swift 6, SwiftUI, macOS 14

---

### Task 1: Reorder and simplify the alert content

**Files:**
- Modify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift`

**Step 1: Replace the split content layout**

Render the physical-notch spacer first, followed by one compact group:

```swift
HStack(spacing: 0) {
    Color.black.frame(width: notchWidth)
    HStack(spacing: 8) {
        animatedBell
        Text(session.kind.notificationTitle)
        pulsingStatusDot
    }
}
```

Expected: the visible order is bell, text, green dot; no element sits inside the bell.

**Step 2: Remove the bell background**

Keep only the white `bell.fill` symbol and its decaying ring rotation. Remove the grey filled and stroked circle.

**Step 3: Separate the status animation**

Render a solid green 6-point dot at the right edge of the text with its own expanding/fading green ring.

**Step 4: Update the copy**

Use:

```swift
case .morningPlanning: "Ready to plan your day?"
case .eveningReview: "Ready to review your day?"
```

Update the accessibility label from “Hover to begin” to “Hover to open.”

### Task 2: Round the pending notification window

**Files:**
- Modify: `boringNotch/ContentView.swift`

**Step 1: Add pending-notification corner values**

When the notch is closed and a workflow is pending, return larger top and bottom radii before the normal closed-notch scaling logic.

Expected: the compact notification has visibly softer, pill-like corners while normal notch geometry remains unchanged.

**Step 2: Match layout sizing**

Pass zero spacer width on displays without a physical notch and update `computedChinWidth` to match the revised notification content.

### Task 3: Verify and relaunch

**Files:**
- Verify: `boringNotch/ContentView.swift`
- Verify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift`

**Step 1: Run source checks**

Run `git diff --check`.

Expected: no output.

**Step 2: Run package tests**

Run `swift test --disable-sandbox`.

Expected: all daily-planning core tests pass.

**Step 3: Follow the requested Debug lifecycle**

Close the running Debug app, delete only `dev.codex.boringnotch.dailyplanning` preferences, rebuild the Debug bundle, and reopen it.

Expected: the full build succeeds and the reset app opens at onboarding without changing Apple Reminders data.
