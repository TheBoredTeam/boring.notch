# Codex Notification Presentation Timing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement the plan task-by-task.

**Goal:** Make passive Codex notices use the same direct SwiftUI insertion/removal boundary as the daily planning/review reminder and keep the prompt stationary for exactly three seconds after its entrance response.

**Architecture:** The Codex manager owns notification state and a presentation-scoped dismissal task, while the prompt view starts that task from `onAppear`. The closed-notch parent uses the daily workflow’s single `StandardAnimations.open` transaction and the existing opacity/scale/top transition; passive notices have no event-time expiry.

**Tech Stack:** Swift 5.10, SwiftUI, Foundation, Defaults, XCTest, Xcode Debug build.

---

### Task 1: Lock the presentation timing contract

**Files:**
- Modify: `boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`
- Test: `boringNotchTests/CodexNotificationsCoreTests.swift`

Add a 0.42-second entrance response and a three-second passive dwell. Expose a pure delay function that accounts for the animation speed setting and disabled-animation mode. Keep passive notifications without an event-time expiry; permission callbacks retain their own expiry.

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-swift-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache swift test --disable-sandbox --scratch-path /tmp/boring-notch-swiftpm-cache
```

Expected: all core tests pass, including exact 3.42-second enabled-animation delay and exact 3-second disabled-animation delay.

### Task 2: Start and finish passive lifecycle from the prompt

**Files:**
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`

Start one manager-owned task when a passive prompt appears, keyed by notification ID and creation token. Sleep for entrance response plus the three-second dwell, then remove the matching notification in the daily spring transaction. Cancel presentation tasks when the manager stops or a newer token replaces one.

### Task 3: Match the daily reminder render boundary

**Files:**
- Modify: `boringNotch/ContentView.swift`
- Verify: `boringNotch/components/Notch/ClosedNotchRenderer.swift`

Restore the daily workflow’s parent animation keyed to the selected closed presentation. Keep the transition on the conditional extension child and fixed-size the activity layout so width/shape changes animate with the same spring instead of competing model and implicit animations.

### Task 4: Build and verify

Run the focused test command, `git diff --check`, and:

```bash
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications build -quiet
```

Expected: tests and build pass; unrelated working-tree changes remain unstaged.
