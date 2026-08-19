# Bidirectional Codex Permission Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show Codex's native approval card and Boring Notch's expanded permission card at the same time, while making Allow or Deny in either surface resolve the same pending request without focus stealing or UI flicker.

**Architecture:** Keep `PermissionRequest` asynchronous so Codex proceeds to its native prompt while Boring Notch mirrors the event. Treat the native Codex approval card as the authority. Before sending a notch decision, verify that Codex exposes a live approval surface through Accessibility, then deliver Codex's own approval shortcut directly to the Codex process and wait for that surface to disappear. Native Codex decisions continue to dismiss the mirror through prompt observation and lifecycle hooks. Do not use async hook output as a decision channel because Codex explicitly ignores control output from background hooks.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit Accessibility APIs, Core Graphics PID-targeted keyboard events, Python 3 Codex hooks, XCTest, Xcode Debug build.

---

### Task 1: Preserve the supported dual-window hook contract

**Files:**
- Verify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Verify: `boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`
- Verify: `boringNotchTests/CodexNotificationsCoreTests.swift`

**Step 1:** Keep only `PermissionRequest` configured with `"async": true` so Boring Notch receives the request without delaying Codex's native prompt.

**Step 2:** Keep the hook output informational (`{}`) and retain the exact accessibility control marker in the mirrored payload.

**Step 3:** Run the focused core tests and confirm parsing, persistence, and `PostToolUse` cleanup remain intact.

### Task 2: Replace focus-stealing button automation with Codex command shortcuts

**Files:**
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`

**Step 1:** Broaden approval-surface discovery to accept the interactive roles used by Chromium accessibility elements, while still requiring a paired Allow and Deny surface.

**Step 2:** Remove AX press and pointer-position click behavior. Map Allow to Return and Deny to Escape, matching Codex's current approval command bindings.

**Step 3:** Post key-down and key-up events directly to the running `com.openai.codex` process with `CGEvent.postToPid`, leaving Boring Notch and Codex windows in place.

**Step 4:** Report success only after the verified native approval surface disappears; otherwise fail closed and leave the mirrored card actionable.

### Task 3: Keep failure UX stable and recoverable

**Files:**
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`

**Step 1:** Stop activating Codex automatically when a notch decision fails, because that collapses the expanded notch before the user can read the error.

**Step 2:** Keep the error and actions visible without adding a separate recovery button. Let the compact notch permission prompt open Codex when clicked, while hover continues to expand it for review.

**Step 3:** Preserve the loading state until Codex confirms the decision and collapse only after success.

### Task 4: Verify native-to-notch and notch-to-native synchronization

**Files:**
- Verify: `boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Verify: `boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`
- Verify: `boringNotchTests/CodexNotificationsCoreTests.swift`

**Step 1:** Confirm native prompt observation dismisses only the matching persistent permission notification after the prompt was seen and then disappears.

**Step 2:** Confirm Allow and Deny from Boring Notch leave Codex focused state unchanged and dismiss both surfaces only after resolution.

**Step 3:** Confirm a failed relay leaves both notch actions available and does not dismiss or activate another app.

### Task 5: Build and prepare the manual Case 3 test

**Files:**
- Verify: `/Users/paradox/.codex/hooks.json`
- Verify: `/Users/paradox/.codex/boring-notch-notify.py`

**Step 1:** Run `swift test --filter CodexNotificationsCoreTests` with the isolated module caches.

**Step 2:** Run `git diff --check` and build the Debug `boringNotch` scheme into the dedicated DerivedData directory.

**Step 3:** Update the installed hook if its generated script changed, register the rebuilt app, and open only the newest Debug bundle.

**Step 4:** Run manual Case 3 twice: choose once in Boring Notch and once in Codex. Verify both windows initially coexist, either choice resolves the native request, the other surface disappears, and the Desktop test file is absent afterward.
