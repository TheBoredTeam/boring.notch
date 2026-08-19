# Codex Prompt Behavior Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ensure Codex success prompts use one green presentation, passive notices always dismiss when not hovered, expanded permission content remains a fixed-size scroll viewport, and Allow/Deny decisions reach Codex reliably.

**Architecture:** Collapse completed Codex rendering onto the green success style and remove the unused finished-status presentation branch. Keep passive dismissal owned by the notification manager, but make hover state explicit and reset the timer on every pointer exit. Give the expanded permission view an explicit fixed viewport at both the permission view and open-content host boundaries. Install PermissionRequest as a synchronous hook so the localhost callback returns Codex’s official decision response; keep a fallback for expired or legacy callbacks.

**Tech Stack:** Swift 5.10, SwiftUI/AppKit, Python 3 hook script, XCTest, Xcode Debug build.

---

### Task 1: Normalize completed status and passive lifecycle

**Files:**
- Modify: `boring.notch/boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`
- Modify: `boring.notch/boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`
- Modify: `boring.notch/boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Test: `boring.notch/boringNotchTests/CodexNotificationsCoreTests.swift`

Remove the separate `.finished` completed state and classify all non-failure/non-actionable Stop events as `.succeeded`. Render one green checkmark-filled success icon/tint for every successful prompt. Preserve the existing priority and passive timing behavior, while ensuring a pointer exit always schedules a fresh dismissal timer and a new presentation resets stale hover state.

Run: `CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache swift test --filter CodexNotificationsCoreTests --scratch-path /tmp/boring-notch-swiftpm-cache`
Expected: all focused core tests pass, including success classification and passive timing assertions.

### Task 2: Make the expanded permission surface a fixed viewport

**Files:**
- Modify: `boring.notch/boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`
- Modify: `boring.notch/boringNotch/components/Notch/OpenNotchContentView.swift`
- Modify: `boring.notch/boringNotch/ContentView.swift`

Use a named fixed permission viewport height derived from `openNotchSize`, apply it at the host and scroll view, align the scroll content to the top, and avoid any content-size-driven outer frame changes while scrolling or revealing long commands. Keep buttons inside the scroll content’s hit-test region.

Run: `git diff --check`
Expected: no whitespace errors.

### Task 3: Make Allow/Deny decisions authoritative and dismiss cleanly

**Files:**
- Modify: `boring.notch/BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Modify: `boring.notch/BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift`
- Modify: `boring.notch/boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift`
- Modify: `boring.notch/boringNotch/XPCHelperClient/XPCHelperClient.swift`
- Modify: `boring.notch/boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Modify: `boring.notch/boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`
- Modify: `boring.notch/boringNotch/components/Settings/Views/CodexNotificationSettingsView.swift`

Install the PermissionRequest hook as synchronous, preserve token/expiry validation, return the official allow/deny hook response to Codex, and remove the separate Accessibility press path that cannot authorize a synchronous callback. Submit the decision through the callback, clear the expanded and closed prompts after a successful response, and show Open Codex only when no usable callback exists or the callback has expired.

Run: `CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache xcodebuild -project boring.notch/boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications build -quiet`
Expected: the Debug app builds successfully.

### Task 4: Final verification

Run:
- `CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache swift test --filter CodexNotificationsCoreTests --scratch-path /tmp/boring-notch-swiftpm-cache`
- `git diff --check`
- the Debug Xcode build above

Expected: focused tests, whitespace validation, and build all succeed; manual verification should cover success, failure, permission, scrolling, and Allow/Deny behavior.
