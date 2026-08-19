# Codex Background Action and Compact Selection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep Allow/Deny responses background-safe and prevent compact Codex prompt selection from opening the notch detail window.

**Architecture:** The permission helper will use the matched accessibility control and Codex process ID without activating or raising Codex during its retry path. The closed-notch renderer will notify `ContentView` when a selectable activity is tapped, allowing the parent to cancel and suppress its pending hover expansion until the pointer exits.

**Tech Stack:** SwiftUI, AppKit Accessibility APIs, Xcode Debug build.

---

### Task 1: Keep permission responses in the background

**Files:**
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`

Remove application activation, window raising, and main-window changes from `confirmCodexPermissionControl`. Retain accessibility focus on the matched control and process-targeted Return events so the permission relay can still complete without interrupting the user’s current screen.

Expected result: Allow/Deny never brings Codex to the foreground as a side effect.

### Task 2: Suppress expansion after compact selection

**Files:**
- Modify: `boringNotch/components/Notch/ClosedNotchRenderer.swift`
- Modify: `boringNotch/ContentView.swift`

Add a renderer selection callback. On selectable activity tap, cancel the hover task, mark expansion suppressed for the current pointer pass, and keep the notch closed. Clear suppression when the pointer leaves the notch.

Expected result: Clicking the compact prompt runs its Codex navigation action without opening the expanded permission view.

### Task 3: Verify and relaunch

Run `git diff --check`, the focused Swift tests, and the Debug Xcode build. Restart the Debug app and manually verify:

1. Allow/Deny completes without bringing Codex forward.
2. Clicking the compact prompt opens Codex but leaves Boring Notch closed.
3. Hovering without clicking still opens the permission view after the configured boundary.
