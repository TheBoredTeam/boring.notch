# Codex Permission Prompt Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Codex permission notifications clear and actionable, preserve Codex as the fallback approval surface, and align the closed and expanded notch layouts with the requested status/project presentation.

**Architecture:** Keep hook delivery and permission relay behavior unchanged. Extend the notification model with the full user prompt and project context, use a short title only in the closed prompt, and render the full prompt/details in the expanded permission view. Keep closed permission taps routed to Codex while expanded buttons use the existing validated relay and all successful decisions clear the notification.

**Tech Stack:** Swift 5.10, SwiftUI, Foundation, XCTest, Xcode Debug build.

---

### Task 1: Extend notification context and status copy

**Files:**
- Modify: `boring.notch/boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`
- Modify: `boring.notch/boringNotchTests/CodexNotificationsCoreTests.swift`

Add the full submitted prompt and a project label derived from `cwd` to `CodexJobNotification`. Keep the closed title as a collapsed prompt with an ellipsis, while exposing the unabridged prompt for the expanded view. Change the visible status labels to `Success`, `Failure`, `Permission Required`, `Decision Required`, and `Manual Check`; keep generic completed events rendered as `Success` rather than exposing the old `Finished` label. Add parser/state assertions for the full prompt and project label.

Run the focused core test command and verify it passes.

### Task 2: Update closed notification content and interaction

**Files:**
- Modify: `boring.notch/boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`
- Modify: `boring.notch/boringNotch/extensions/NotchExtensionRegistry.swift`
- Modify: `boring.notch/boringNotch/components/Notch/ClosedNotchRenderer.swift`

Render the closed prompt as `short prompt title` on the first line and `status · project` on the second line; never use `resultSummary` or assistant reply text there. Keep the compact permission activity non-expanding on click, route its selection to Codex, and offset the Codex activity left so it is not centered in the host window. Preserve hover expansion for permission review.

### Task 3: Make expanded permission details complete and dismiss reliably

**Files:**
- Modify: `boring.notch/boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`
- Modify: `boring.notch/boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Modify: `boring.notch/boringNotch/components/Notch/OpenNotchContentView.swift`

Show the full user prompt in the expanded permission view, remove truncating line limits from the description, command, and additional input, and use one vertical scroll region for long requests. Keep Allow/Deny wired to the existing relay when a callback exists; otherwise show the Codex fallback action. Ensure a successful relay, an expired/invalid request routed to Codex, or a subsequent Codex completion clears the expanded view and closed prompt.

### Task 4: Validate and reset the Debug app

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-swift-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache swift test --disable-sandbox --scratch-path /tmp/boring-notch-swiftpm-cache
git diff --check
xcodebuild -project boring.notch/boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications build -quiet
```

Quit other `boringNotch` instances and open only `/Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications/Build/Products/Debug/boringNotch.app` for manual verification. Check permission, success, and failure prompts, including closed-title truncation, project context, full expanded details, Allow/Deny dismissal, and the closed prompt’s Codex handoff.
