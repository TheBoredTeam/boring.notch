# Codex Hover Animation Regression Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement the plan task-by-task.

**Goal:** Restore the existing normal notch hover open/close animation without widening Codex-specific state into the shared notch animation path.

**Architecture:** Keep the shared `ContentView` animation keyed by the original boolean that only tracks whether the Codex activity exists. Codex prompt transitions remain owned by the Codex notification manager and its prompt view, so notification identity changes do not drive unrelated notch animations.

**Tech Stack:** Swift 5.10, SwiftUI/AppKit, Xcode Debug build.

---

### Task 1: Restore the shared hover animation trigger

**Files:**
- Modify: `boring.notch/boringNotch/ContentView.swift:126-129,253-256`

**Step 1: Apply the minimal change**

Restore `isShowingCodexPrompt` as the shared container’s animation value. Do not change the existing `vm.notchState` animation or any gesture handling.

**Step 2: Verify the diff scope**

Run: `git diff --check`
Expected: no whitespace errors; only the intended animation discriminator changes.

### Task 2: Build and manually verify

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
xcodebuild -project boring.notch/boringNotch.xcodeproj -scheme boringNotch \
-configuration Debug \
-derivedDataPath /Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications \
build -quiet
```

Expected: the Debug target builds successfully. Launch the rebuilt app and verify the normal notch opens on hover and closes with its existing animation timing.
