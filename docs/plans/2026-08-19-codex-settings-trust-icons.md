# Codex Settings Trust and Icon Corrections Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the Codex settings screen accurately report disabled/untrusted hooks, use the same blue sidebar treatment as the other apps, and show only the real notification types with the notch glyphs.

**Architecture:** Keep hook-state parsing in a small pure helper value that the unsandboxed XPC service consumes and the Swift package tests exercise. Reuse `CodexJobStatus` for notification glyph names so the settings menu and notch prompt cannot drift apart. Use the supplied transparent Codex PNG as a template asset for the blue sidebar icon.

**Tech Stack:** SwiftUI, AppKit, NSXPC, Swift Package Manager tests, Codex `hooks.json` and `config.toml` state.

---

### Task 1: Reproduce and lock down disabled-hook trust behavior

**Files:**
- Create: `BoringNotchXPCHelper/CodexHookTrustState.swift`
- Modify: `Package.swift`
- Modify: `boringNotchTests/CodexNotificationsCoreTests.swift`

**Steps:**
1. Add a focused test fixture with valid `trusted_hash` values plus `enabled = false` and assert the affected section is not trusted.
2. Run the focused test and confirm it fails against the current hash-only behavior.
3. Implement the pure parser so valid hashes are required and any explicit `enabled = false` marks that section untrusted.
4. Run the focused test again and confirm it passes.

### Task 2: Connect the corrected trust parser to the XPC helper

**Files:**
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`

**Steps:**
1. Keep the existing expected hook-section discovery from `hooks.json`.
2. Pass the TOML contents through `CodexHookTrustState` and require every expected section to be trusted.
3. Preserve `false` for missing/malformed configuration.

### Task 3: Correct settings iconography and sidebar tint

**Files:**
- Modify: `boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`
- Create: `boringNotch/Assets.xcassets/codexIcon.imageset/codex.png`
- Create: `boringNotch/Assets.xcassets/codexIcon.imageset/Contents.json`
- Modify: `boringNotch/components/Settings/SettingsView.swift`
- Modify: `boringNotch/components/Settings/Views/CodexNotificationSettingsView.swift`

**Steps:**
1. Expose the notch status glyph from `CodexJobStatus` and remove the duplicate private mapping.
2. Render the supplied transparent Codex PNG as a blue template image in the sidebar.
3. Remove the nonexistent Working row.
4. Use the status glyphs for Success, Failure, Permission Required, Decision Required, and Manual review.
5. Use a red failure state for any untrusted hook while retaining the Codex hooks deep link.

### Task 4: Build and verify

**Commands:**

```bash
git -C boring.notch diff --check
swift test --filter CodexNotificationsCoreTests --scratch-path /tmp/boring-notch-swiftpm-cache
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
xcodebuild -project boring.notch/boringNotch.xcodeproj -scheme boringNotch \
  -configuration Debug \
  -derivedDataPath /Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications \
  build -quiet
```

**Expected:** The disabled-hook fixture fails before the parser fix and passes after it; all focused tests pass; the Debug build succeeds; and the settings menu has five rows with matching notch glyphs.
