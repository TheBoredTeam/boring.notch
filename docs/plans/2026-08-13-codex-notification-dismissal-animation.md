# Codex Notification Dismissal Animation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make passive Codex notch prompts use the daily planning/review transition pattern and remain visible for exactly three seconds before their dismissal animation begins.

**Architecture:** Keep the existing `CodexClosedNotchPrompt` transition and animate the outer closed-notch presentation when the selected presentation changes, matching the daily workflow’s visibility animation. Preserve live permission expiry and relay behavior; shorten only passive notification lifetimes.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, Xcode Debug build.

---

## Corrected implementation after manual regression

The first implementation attached an implicit animation below the snapshot boundary and removed the model outside an animation transaction. That does not preserve the disappearing `AnyView`, so no removal transition is rendered. The corrected implementation must:

1. attach the opacity/scale/top-move transition to `activity.content` in `ClosedNotchRenderer`, the same conditional insertion/removal boundary used by daily planning;
2. mutate notification state inside `withAnimation(StandardAnimations.open/close)` for arrival and dismissal;
3. schedule passive removal after the 0.45-second opening-animation budget plus a full 3-second stationary dwell; the 0.45-second closing animation begins only after that deadline.

### Task 1: Lock the three-second passive lifetime

**Files:**
- Modify: `boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`
- Modify: `boringNotchTests/CodexNotificationsCoreTests.swift`
- Modify: `boringNotch/components/Settings/Views/CodexNotificationSettingsView.swift`

**Step 1: Update the failing expectations**

Change the passive decision, manual-check, and finished notification expectations from 12 seconds to 3 seconds and update the settings copy to describe all passive notices as three-second notices.

**Step 2: Run the focused tests**

Run: `CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-swift-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache swift test --disable-sandbox --scratch-path /tmp/boring-notch-swiftpm-cache`

Expected: FAIL until `notificationLifetime` is changed.

**Step 3: Implement the minimal lifetime change**

Keep `.needsAction(.permission)` returning `nil`; return `3` for every other status.

**Step 4: Run the focused tests again**

Expected: all Codex notification tests pass.

### Task 2: Animate closed-notch presentation changes

**Files:**
- Modify: `boringNotch/ContentView.swift`
- Verify: `boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`

**Step 1: Preserve the existing prompt transition**

Keep the Codex prompt’s opacity/scale/top movement transition, which mirrors the daily workflow prompt.

**Step 2: Animate the outer closed presentation**

Add a `StandardAnimations.open` animation keyed to `closedSnapshot?.presentation.primary` beside the existing notch-state animation. This animates both the prompt’s insertion and its removal, including the closed-notch geometry change back to the normal presentation.

**Step 3: Build**

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/boring-notch-codex-derived build`

Expected: `BUILD SUCCEEDED`.

### Task 3: Validate the visible dwell and dismissal

**Files:**
- Verify: `boringNotch/ContentView.swift`
- Verify: `boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`

**Step 1: Run all tests**

Run the Swift package test command from Task 1. Expected: all tests pass.

**Step 2: Manually inspect a synthetic passive result**

Send a temporary local `Stop` event to the Debug app. Confirm the prompt appears with the daily-workflow-style transition, remains for about three seconds excluding the dismissal animation, then fades/scales away while the closed notch returns to its normal presentation.

**Step 3: Verify permission regression**

Confirm a live permission prompt remains actionable until its hook deadline and still uses the existing Allow/Deny relay path.

**Step 4: Review the diff**

Run: `git diff --check` and confirm no unrelated files are modified.
