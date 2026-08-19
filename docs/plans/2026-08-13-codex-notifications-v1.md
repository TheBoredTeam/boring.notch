# Codex Notifications V1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the Codex chat destination with concise, action-oriented notch notifications that identify the job, report its outcome, and say when the user must review a permission, decision, or manual check.

**Architecture:** Codex lifecycle hooks provide passive `UserPromptSubmit`, `PermissionRequest`, and `Stop` events through a local URL scheme. A Foundation-only core correlates events by session/turn, classifies their status conservatively, and maintains a deduplicated priority queue; SwiftUI renders only the highest-priority item in the closed notch. The integration never creates a Codex conversation and never answers an approval.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit URL handling, NSXPCConnection for opt-in hook configuration, Codex hooks JSON, Swift Package Manager/XCTest, Xcode Debug build.

---

### Task 1: Notification event core

**Files:**
- Create: `boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`
- Modify: `Package.swift`
- Create: `boringNotchTests/CodexNotificationsCoreTests.swift`
- Delete: `boringNotch/features/CodexChat/Core/CodexChatCore.swift`
- Delete: `boringNotchTests/CodexChatCoreTests.swift`

**Step 1: Write failing hook parsing and queue tests**

Cover job-title capture from `UserPromptSubmit`, permission notices, stop-result summaries, explicit failure phrases, conservative manual-test and decision detection, action-required priority, replacement of stale notices for the same turn, and completion expiry.

**Step 2: Run the tests to verify they fail**

Run: `swift test`

Expected: FAIL because `CodexNotificationsCore` does not exist.

**Step 3: Implement the minimal core**

Define `CodexHookEvent`, `CodexJobNotification`, `CodexJobStatus`, `CodexRequiredAction`, `CodexNotificationState`, and `PriorityResolver`. Parse only documented hook fields, collapse whitespace, keep summaries bounded, and never claim success or failure without an explicit signal.

**Step 4: Run the tests to verify they pass**

Run: `swift test`

Expected: all notification core tests pass.

### Task 2: Passive Codex hook ingress

**Files:**
- Modify: `boringNotch/Info.plist`
- Modify: `boringNotch/boringNotchApp.swift`
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift`
- Modify: `boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift`
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Modify: `boringNotch/XPCHelperClient/XPCHelperClient.swift`
- Delete: `BoringNotchXPCHelper/CodexAppServerService.swift`

**Step 1: Register a local URL ingress**

Register `boringnotch://codex-event?payload=<base64url-json>` and forward matching URLs from `AppDelegate` to the notification manager. Reject malformed, oversized, or unrelated payloads without changing state.

**Step 2: Replace app-server lifecycle methods with hook configuration**

Add XPC methods to query, install, and remove Boring Notch hook entries in `~/.codex/hooks.json`. Preserve every unrelated key and hook, refuse to overwrite malformed JSON, and identify owned entries by the `boringnotch://codex-event` marker.

**Step 3: Keep hooks passive**

Install `UserPromptSubmit`, `PermissionRequest`, and `Stop` command hooks. Each hook forwards stdin JSON through the custom URL and returns `{}` so Codex retains its native permission and decision flow.

**Step 4: Compile the helper and app targets**

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/boring-notch-codex-derived CODE_SIGNING_ALLOWED=NO build`

Expected: BUILD SUCCEEDED.

### Task 3: Notification-only notch experience

**Files:**
- Create: `boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Create: `boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`
- Modify: `boringNotch/extensions/NotchExtensionRegistry.swift`
- Modify: `boringNotch/components/Notch/ClosedNotchPresentation.swift`
- Modify: `boringNotch/components/Notch/ClosedNotchRenderSnapshot.swift`
- Modify: `boringNotch/components/Notch/ClosedNotchRenderer.swift`
- Modify: `boringNotch/ContentView.swift`
- Delete: `boringNotch/features/CodexChat/CodexAppServerClient.swift`
- Delete: `boringNotch/features/CodexChat/CodexChatManager.swift`
- Delete: `boringNotch/features/CodexChat/CodexChatExtension.swift`
- Delete: `boringNotch/features/CodexChat/CodexChatView.swift`

**Step 1: Remove the conversation destination**

Restore the built-in Home/Shelf destination model and remove every Codex tab, composer, transcript, workspace picker, and approval button. Keep only the generic closed-notch activity seam.

**Step 2: Render one concise job notification**

Use a status symbol, a bounded job title, and one second line:

- `Needs permission · Open Codex`
- `Decision needed · Open Codex`
- `Manual check · Review result`
- `Failed · Review result`
- `Finished · No action needed`

Pulse only action-required states. Use amber for attention, red for failure, green for verified success, and neutral blue/white for finished work.

**Step 3: Apply queue behavior**

Show action-required items before failures and failures before finished work. Keep permission, decision, manual-check, and failed notices until selected; expire ordinary completion after 12 seconds; replace stale notices from the same turn.

**Step 4: Route selection back to Codex**

Selecting a notice launches ChatGPT/Codex if installed and dismisses the selected notice. Boring Notch does not approve, deny, reply, or send a new instruction.

### Task 4: Opt-in setup and verification

**Files:**
- Create: `boringNotch/components/Settings/Views/CodexNotificationSettingsView.swift`
- Modify: `boringNotch/components/Settings/SettingsView.swift`
- Modify: `boringNotch.xcodeproj/project.pbxproj`
- Delete: `docs/plans/2026-08-13-codex-chat-v1.md`

**Step 1: Add an integration settings page**

Explain what is shown, offer Install/Remove actions, and show the required final step: restart Codex and trust the Boring Notch hooks through `/hooks`. Do not request an API key or filesystem entitlement.

**Step 2: Remove obsolete project references**

Delete all Codex chat/app-server build references and add only the notification core, manager, extension, and settings files.

**Step 3: Run complete verification**

Run: `swift test`

Expected: all tests pass.

Run: `git diff --check`

Expected: no output.

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/boring-notch-codex-derived CODE_SIGNING_ALLOWED=NO build`

Expected: BUILD SUCCEEDED.

**Step 4: Exercise the Debug UI without changing the user's hooks**

Launch the Debug app and send fixture URLs for permission, failure, completion, and manual-check events. Confirm priority, color, copy, expiry, and click behavior. Do not click Install or modify `~/.codex/hooks.json` during verification.
