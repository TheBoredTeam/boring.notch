# Codex Notification Explicit Presentation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give passive Codex success and failure prompts deterministic daily-planning-style entrance and exit animations with exactly three stationary seconds between them.

**Architecture:** Separate the notification model from the notification currently mounted in the closed-notch renderer. The manager stages each passive prompt through mount, animated presentation, three-second dwell, animated removal, and post-animation model cleanup so extension-registry invalidation cannot skip the transition.

**Tech Stack:** Swift 5.10, SwiftUI, Foundation, Defaults, XCTest, Xcode Debug build.

---

### Task 1: Define the animation timing contract

**Files:**
- Modify: `boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`
- Test: `boringNotchTests/CodexNotificationsCoreTests.swift`

**Step 1:** Replace the combined passive-presentation delay helper with separate entrance, dwell, and exit durations derived from the animation setting and speed multiplier.

**Step 2:** Test that enabled animations produce a 0.42-second entrance, a fixed 3-second dwell, and a 0.42-second exit at 1x; disabled animations produce zero entrance/exit with the same 3-second dwell.

**Step 3:** Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-swift-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache swift test --disable-sandbox --scratch-path /tmp/boring-notch-swiftpm-cache
```

Expected: all focused core tests pass.

### Task 2: Stage passive prompt presentation explicitly

**Files:**
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`

**Step 1:** Add manager-owned mounted/presented notification state and replace the obsolete per-view `onAppear` dismissal tasks.

**Step 2:** On a passive result, mount the notification without animation, yield one presentation turn, animate it into the renderer, wait for entrance plus exactly three seconds, animate it out, wait for the exit, and then dismiss it from model state.

**Step 3:** Keep permission prompts mounted and persistent until their existing decision or expiry flow removes them.

### Task 3: Key the daily-style parent animation to presentation state

**Files:**
- Modify: `boringNotch/ContentView.swift`
- Verify: `boringNotch/components/Notch/ClosedNotchRenderer.swift`

**Step 1:** Drive the parent `StandardAnimations.open` transaction from the explicit Codex presentation token rather than a derived Boolean.

**Step 2:** Preserve the existing opacity/scale/top transition on the conditional extension activity.

### Task 4: Verify the result

**Step 1:** Run the focused Swift tests.

**Step 2:** Run `git diff --check`.

**Step 3:** Run:

```bash
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications build -quiet
```

Expected: tests and build pass, and unrelated working-tree changes remain untouched.
