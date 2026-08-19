# Codex Notch Action and Hover Boundary Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep Allow/Deny actions in the notch local to the permission relay, while giving users a slightly longer compact-prompt hover window before the permission detail view expands.

**Architecture:** Compact-prompt taps will remain the only path that opens the originating Codex thread. Permission submission will call the accessibility relay directly. A Codex-specific minimum hover delay will be applied in `ContentView` without changing the user’s general notch hover preference.

**Tech Stack:** SwiftUI, AppKit, Swift Package Manager XCTest, Xcode Debug build.

---

### Task 1: Remove navigation from permission actions

**Files:**
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationManager.swift`

Remove the `openCodex(for:)` call from `submitPermissionDecision`. Keep `openCodex(for:)` available for the compact prompt’s `onSelect` handler.

Expected result: Allow/Deny invokes the existing XPC permission decision path without activating or navigating Codex.

### Task 2: Add a Codex-only hover boundary

**Files:**
- Modify: `boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`
- Modify: `boringNotch/ContentView.swift`
- Test: `boringNotchTests/CodexNotificationsCoreTests.swift`

Add a named Codex hover-expansion delay greater than the current default of `0.3` seconds, use it as a lower bound only when the active closed activity explicitly requests hover expansion, and preserve the configured general delay for other content. Add a test that locks the new boundary value.

Expected result: Hovering a permission prompt for a short moment leaves it compact; sustained hover opens the detail view after the new delay.

### Task 3: Verify and relaunch

Run:

```bash
git diff --check
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
swift test --filter CodexNotificationsCoreTests \
  --scratch-path /tmp/boring-notch-swiftpm-cache
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Debug \
  -derivedDataPath /Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications \
  build -quiet
```

Then restart the Debug app and manually verify:

1. Hovering the compact permission prompt does not immediately expand it.
2. The prompt expands after the longer hover boundary.
3. Allow/Deny does not open Codex.
4. Clicking the compact prompt still opens the originating Codex chat.
