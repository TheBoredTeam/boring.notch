# Preserve HUD/OSD Isolation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep the daily planning/review feature isolated from existing HUD/OSD behavior and produce a local app whose XPC helper has a valid, distinct bundle identifier.

**Architecture:** Treat `upstream/dev` as the PR baseline and `v2.7.3` only as the behavioral reference represented by the backup app. Limit source changes to the daily-workflow integration point in `ContentView.swift`; do not revert or edit upstream OSD implementation files. Build the local validation app without a global `PRODUCT_BUNDLE_IDENTIFIER` override so the app and embedded XPC helper retain distinct identifiers.

**Tech Stack:** Swift 6, SwiftUI, XCTest/Swift Testing, Xcode build system, macOS XPC services.

---

### Task 1: Establish change provenance

**Files:**
- Inspect: `boringNotch/ContentView.swift`
- Inspect: `boringNotch/boringNotchApp.swift`
- Inspect: `boringNotch/components/OSD/**`

**Step 1: Compare the feature with its required PR base**

Run: `git diff --name-status upstream/dev...HEAD`

Expected: only daily-planning files plus the small app integration files are changed; no file below `boringNotch/components/OSD/` is listed.

**Step 2: Compare the release reference with the PR base**

Run: `git log --oneline v2.7.3..upstream/dev -- boringNotch/components/OSD boringNotch/observers/MediaKeyInterceptor.swift`

Expected: upstream commits, including `3869c42`, account for the HUD-to-OSD refactor independently of this feature branch.

### Task 2: Prevent workflow activation over higher-priority UI

**Files:**
- Modify: `boringNotch/ContentView.swift`
- Test: `boringNotchTests/DailyPlanningCoreTests.swift`

**Step 1: Confirm presentation-policy coverage**

Run: `rg -n "shouldShowPendingPrompt|isClosedOSDVisible|isPowerNotificationVisible|isGreetingAnimationVisible" boringNotchTests/DailyPlanningCoreTests.swift`

Expected: tests cover suppression for OSD, power notification, and greeting animation.

**Step 2: Apply the minimal integration fix**

Use `isShowingPendingWorkflowNotification`, rather than the raw pending-session flag, when deciding whether a hover or tap may activate a daily workflow. Restore unrelated formatting and retain the original inline battery-notification rendering condition.

**Step 3: Run focused tests**

Run: `swift test --disable-sandbox`

Expected: all daily-planning tests pass.

### Task 3: Verify source isolation

**Files:**
- Inspect: all files in `git diff upstream/dev...HEAD`

**Step 1: Check whitespace and accidental edits**

Run: `git diff --check`

Expected: no output.

**Step 2: Confirm untouched shared subsystems**

Run: `git diff --name-only upstream/dev...HEAD | rg 'components/OSD|MediaKeyInterceptor|BrightnessManager|VolumeManager|OSDSettingsView'`

Expected: no output.

**Step 3: Build the app**

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/boring-notch-hud-isolation-build build`

Expected: `** BUILD SUCCEEDED **`.

### Task 4: Validate and install the corrected app bundle

**Files:**
- Build output: `/tmp/boring-notch-hud-isolation-build/Build/Products/Debug/boringNotch.app`
- Install target: `/Applications/boringNotch.app`

**Step 1: Inspect bundle identifiers**

Run: `plutil -p` on the app and embedded helper `Info.plist` files.

Expected: the main app is `theboringteam.boringnotch`; the helper is `theboringteam.boringnotch.BoringNotchXPCHelper`.

**Step 2: Preserve and replace the current installation**

Move the current feature app to a dated recoverable backup, then copy the corrected build to `/Applications/boringNotch.app`.

**Step 3: Verify signatures and embedded helper**

Run: `codesign --verify --deep --strict /Applications/boringNotch.app`

Expected: exit status 0 and an embedded XPC helper with a distinct identifier.

### Task 5: Report scope and limitations

**Files:**
- No additional changes.

**Step 1: Summarize the audit**

Report feature-owned changes, inherited upstream differences from v2.7.3, verification results, local-install backup paths, and any manual accessibility/OSD validation still required.
