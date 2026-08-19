# Codex Permission Mirror and Test Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restore the live PermissionRequest mirror by regenerating the current synchronous Debug hook and make the permission manual test remove its Desktop artifact after Allow.

**Architecture:** Keep the native Codex permission prompt and the notch mirror on the existing loopback callback path. Treat stale installed hook state as an installation problem, surface the current hook status in Debug Settings, and make the manual test prompt itself require read-back, deletion, and post-delete verification.

**Tech Stack:** SwiftUI/AppKit Debug app, generated Python Codex hook, Codex hooks JSON, Markdown manual-test documentation, SwiftPM/XCTest.

---

### Task 1: Make Case 3 self-cleaning

**Files:**
- Modify: `AGENT.md`

Update the copy-pasteable permission prompt so an approved request creates the Desktop file, reads it, deletes it, and verifies the path no longer exists. Keep the target outside the workspace and require approval before the write.

### Task 2: Refresh the installed Debug hook

**Files:**
- Verify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Verify: `boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`
- Verify: `/Users/paradox/.codex/hooks.json`
- Verify: `/Users/paradox/.codex/boring-notch-notify.py`

Use Debug Settings’ Codex “Connect or update Codex” action. Confirm the installed PermissionRequest hook has timeout 75, no `async: true`, and no obsolete `control` metadata. Confirm the Debug app reports Connected.

### Task 3: Remove the current test artifact

**Files:**
- Delete recoverably: `/Users/paradox/Desktop/codex-notification-permission-test.txt`

Move the already-approved test artifact off the Desktop, then verify the original path is absent.

### Task 4: Validate the fix

Run:

```bash
git diff --check
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
swift test --filter CodexNotificationsCoreTests \
  --scratch-path /tmp/boring-notch-swiftpm-cache
```

Expected: no whitespace errors and all focused tests pass. For manual validation, restart Codex, run Case 3 from `AGENT.md`, confirm the notch mirror appears with Allow/Deny, and confirm the Desktop path is absent after Allow.
