# Codex Permission Sources Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the first Codex notification version present permission requests from any Codex tool, including Browser-style requests, through the existing notch permission flow.

**Architecture:** Keep the existing `PermissionRequest` hook and callback relay; they already carry a tool name and bounded tool input. Remove shell-only copy, add source-aware display names and icons for common tools, and add a parser regression test using a Browser request. This covers permission requests emitted by Codex hooks; the Codex desktop agent’s own browser-automation confirmation is outside the hook API and cannot be intercepted by Boring Notch.

**Tech Stack:** Swift 5.10, SwiftUI, Swift Package Manager, XCTest, Codex hooks JSON.

---

### Task 1: Prove non-shell permission requests remain actionable

**Files:**
- Modify: `boringNotchTests/CodexNotificationsCoreTests.swift`

**Step 1: Write the regression test**

Add a `PermissionRequest` payload with `tool_name: "Browser"`, a URL in `tool_input`, a description, and a valid callback. Assert that the parser preserves the tool name and input, produces `Permission Required`, and leaves a visible notification with the callback.

**Step 2: Run the focused test**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
swift test --filter CodexNotificationsCoreTests \
  --scratch-path /tmp/boring-notch-swiftpm-cache
```

Expected: the existing suite passes; the new test documents the generic behavior.

### Task 2: Remove shell-only presentation assumptions

**Files:**
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`
- Modify: `boringNotch/components/Settings/Views/CodexNotificationSettingsView.swift`

**Step 1: Add source-aware display mapping**

Map `Bash` to `Terminal`, `Browser` to `Browser`, and `apply_patch` to `File changes` for the expanded request header. Use a browser/globe icon for Browser, a terminal icon for Bash, and the shield fallback for unknown tools.

**Step 2: Generalize Settings copy**

Change the Permission Required description from a shell-only sentence to `A Codex tool needs your Allow or Deny response.`

### Task 3: Validate the feature

**Files:**
- Verify all changed files

**Step 1: Run focused tests and whitespace checks**

Run the focused Swift test command above and `git diff --check`.

Expected: all tests pass and no whitespace errors are reported.

**Step 2: Build Debug**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Debug \
  -derivedDataPath /Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications \
  build -quiet
```

Expected: `BUILD SUCCEEDED`.

**Step 3: Restart only the newest Debug app before manual verification**

After any source change, close existing Boring Notch instances and open only `/Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications/Build/Products/Debug/boringNotch.app`, following `AGENT.md`.
