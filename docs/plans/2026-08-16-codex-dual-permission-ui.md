# Codex Dual Permission UI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Preserve Boring Notch's established hover/open/close behavior while showing a compact actionable permission card beside Codex's native approval prompt and synchronizing decisions in either surface.

**Architecture:** Keep the normal notch view hierarchy and animation modifiers identical to the pre-permission implementation. Layer permission state onto existing handlers, render permission actions in a fixed footer, and install `PermissionRequest` as an asynchronous mirror so Codex can show its native prompt immediately. A token-validated loopback callback authorizes the app's existing unsandboxed helper to press only a visible Codex permission button; while a request is active, the app observes the native prompt and removes the notch notice after a native decision.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit Accessibility APIs, Foundation loopback HTTP, Python 3 Codex hook, XCTest, Xcode Debug build.

---

### Task 1: Lock the dual-surface hook contract with tests

**Files:**
- Modify: `boringNotchTests/CodexNotificationsCoreTests.swift`
- Modify: `boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`

**Step 1: Write the failing tests**

Require permission callback payloads to include `"control":"accessibility"`; reject obsolete callback payloads without that value. Keep `PostToolUse` dismissal coverage.

**Step 2: Run the focused tests and verify failure**

Run: `swift test --filter CodexNotificationsCoreTests`

Expected: the new callback-control assertions fail against the synchronous callback model.

**Step 3: Implement the minimal model change**

Add an accessibility control discriminator to `CodexPermissionCallback` and parse only the current exact payload shape:

```swift
public enum CodexPermissionControl: String, Equatable, Sendable {
    case accessibility
}

public struct CodexPermissionCallback: Equatable, Sendable {
    public let port: Int
    public let token: String
    public let expiresAt: Date
    public let control: CodexPermissionControl
}
```

**Step 4: Run the focused tests**

Expected: all `CodexNotificationsCoreTests` pass.

### Task 2: Restore the established normal notch animation path

**Files:**
- Modify: `boringNotch/ContentView.swift`
- Modify: `boringNotch/components/Notch/OpenNotchContentView.swift`

**Step 1: Compare against the working historical structure**

Use `git show 769af89:boringNotch/ContentView.swift` and retain its main layout modifier ordering, normal `BoringHeader`, and open/close animation ownership.

**Step 2: Remove permission-driven view-tree changes**

Keep tap and gesture modifiers structurally stable. Gate permission-only behavior inside gesture handlers. Remove the outer animation keyed to the closed Codex activity because it changes during normal notch opening.

**Step 3: Implement hover collapse**

On pointer exit from an expanded permission request, clear only `expandedPermissionNotificationID`, close with `StandardAnimations.close`, and retain the underlying permission notification so the compact notch prompt reappears.

**Step 4: Build**

Expected: normal hover expansion compiles with the historical animation structure and permission hover exit returns to the compact prompt.

### Task 3: Pin permission actions in a bounded layout

**Files:**
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`
- Modify: `boringNotch/components/Notch/OpenNotchContentView.swift`

**Step 1: Replace the outer permission ScrollView**

Use a fixed-height `VStack`; keep the header and Allow/Deny footer outside scrolling. Put only prompt, description, and command details inside a bounded inner `ScrollView`.

**Step 2: Preserve the normal open size**

Use the existing 640×190 open notch and its content viewport. Do not change global `openNotchSize`, `windowSize`, or normal home/shelf sizing.

**Step 3: Verify interactions**

Expected: Allow and Deny are visible immediately, long text can scroll without resizing the notch, and wheel scrolling cannot trigger permission close gestures.

### Task 4: Mirror Codex permission prompts and relay notch decisions

**Files:**
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift`
- Modify: `boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift`
- Modify: `boringNotch/XPCHelperClient/XPCHelperClient.swift`
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Modify: `boringNotch/components/Settings/Views/CodexNotificationSettingsView.swift`

**Step 1: Make only PermissionRequest asynchronous**

Install the permission handler with `"async": true`; retain short synchronous hooks for other lifecycle events. The Python handler opens the notch, serves one token-validated callback, and always emits `{}` because background hook output cannot approve a request.

**Step 2: Add narrowly scoped helper actions**

Expose XPC methods to inspect whether a Codex permission surface containing both Allow and Deny controls is visible and to press the requested exact control. Search only the accessibility tree of the running `com.openai.codex` application and fail closed when the pair cannot be identified.

**Step 3: Relay a notch decision**

Validate and consume the loopback callback, ask the helper to press the native Codex control, then dismiss the notch notification only after the Accessibility press succeeds.

**Step 4: Observe native decisions**

While a permission notice is active, poll through XPC until the native prompt has been observed once. If it later disappears, dismiss the matching notch notification. Keep `PostToolUse` as the normal successful-tool cleanup signal.

**Step 5: Update setup copy**

Explain that Accessibility is needed for notch Allow/Deny and that Codex and Boring Notch show the same request simultaneously.

### Task 5: Validate and install the Debug build

**Files:**
- Verify: `AGENT.md`
- Verify: `/Users/paradox/.codex/hooks.json`
- Verify: `/Users/paradox/.codex/boring-notch-notify.py`

**Step 1: Run automated checks**

Run focused SwiftPM tests, `git diff --check`, and the Debug Xcode build with the existing isolated module-cache paths.

Expected: zero test failures, no whitespace errors, and BUILD SUCCEEDED.

**Step 2: Run only the newest Debug app**

Quit older Boring Notch processes, register and open only the DerivedData Debug bundle, and update the Codex connection from its settings.

**Step 3: Trust the changed hook**

Open `/hooks` in Codex and trust the changed asynchronous PermissionRequest definition. Restart/reconnect Codex if requested.

**Step 4: Manual verification**

Verify normal hover open/close animation, permission hover expand/collapse, immediately visible buttons, native and notch prompts together, notch Allow/Deny reaching Codex, native decisions dismissing the notch, and Case 3 file cleanup.
