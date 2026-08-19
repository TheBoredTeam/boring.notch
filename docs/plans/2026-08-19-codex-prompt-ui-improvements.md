# Codex Prompt UI Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Codex notification prompts use the compact surface more efficiently and make the expanded permission handoff easier to discover.

**Architecture:** Keep notification state and permission behavior unchanged. Adjust only the SwiftUI presentation layer: remove the compact prompt’s trailing status dot, remove the expanded header’s close control, and render one prominent `Review in Codex` action in the bottom action row. Retain manager-driven collapse when a permission is resolved or the notch closes automatically.

**Tech Stack:** SwiftUI, AppKit/Xcode, XCTest core notification package.

---

### Task 1: Update the compact closed-notch prompt

**Files:**
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationExtension.swift:175-202`

**Step 1: Remove the trailing dot**

Delete the trailing filled `Circle` from `CodexClosedNotchPrompt.prompt`. Keep the status icon at the leading edge; it communicates the notification state and is distinct from the removable trailing dot shown in the reference image.

**Step 2: Rebalance the freed space**

Reduce the row spacing as needed while retaining the existing fixed prompt width and one-line title/project presentation. Do not change notification text, truncation semantics, or closed-notch activity metrics.

**Validation:** The compact prompt has no trailing dot and the title/status-project text receives the reclaimed horizontal space.

### Task 2: Move the expanded Codex review action

**Files:**
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationExtension.swift:209-337`
- Modify: `boringNotch/components/Notch/OpenNotchContentView.swift:13-25`
- Modify: `boringNotch/ContentView.swift:330-380`

**Step 1: Remove the expanded close control**

Remove the top-right `xmark` button and its obsolete `onDismiss` plumbing. Keep manager/state-driven collapse paths intact for resolved or automatically closed permission views.

**Step 2: Render one bottom-right review action**

Move `Review in Codex` out of `permissionHeader` and into `permissionActions`, aligned to the bottom-right after the Allow/Deny controls. Use plain blue text without a capsule, background container, or icon; preserve its disabled/submitting behavior, and invoke `reviewInCodex()` exactly once.

**Validation:** The expanded view has no top-right cross; the bottom action row contains Allow/Deny on the left and a clear Review in Codex action on the right.

### Task 3: Build and manually verify the presentation

**Commands:**

```bash
git -C boring.notch diff --check
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
swift test --filter CodexNotificationsCoreTests \
  --scratch-path /tmp/boring-notch-swiftpm-cache
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
xcodebuild -project boring.notch/boringNotch.xcodeproj \
  -scheme boringNotch -configuration Debug \
  -derivedDataPath /Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications \
  build -quiet
```

**Expected:** whitespace validation, focused tests, and the Debug build succeed. Launch the freshly built app and verify the compact prompt, expanded permission layout, and single Review in Codex handoff visually.
