# Codex Prompt Layout and Dual Permission Presentation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make expanded Codex prompts reveal only genuinely long user instructions, keep the expanded notch viewport stable while scrolling, and mirror a live permission request in both Codex and the notch until either surface decides it.

**Architecture:** Keep the notification model as the single source of truth. The expanded SwiftUI view will use a fixed outer viewport with a scrollable inner content region and independently gated prompt disclosure. The `PermissionRequest` hook runs asynchronously so Codex’s native prompt is not delayed; the notch receives a short-lived callback token and uses the app’s existing Accessibility-authorized helper to press the native Allow/Deny control. A `PostToolUse` event clears the mirror after a native decision.

**Tech Stack:** SwiftUI/AppKit, Foundation URLSession, Python 3 command hook, XCTest, Xcode Debug build.

---

### Task 1: Define the prompt-disclosure and stable-viewport behavior

**Files:**
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`
- Test: `boringNotchTests/CodexNotificationsCoreTests.swift` only if a pure threshold helper is extracted

**Step 1: Inspect the current expanded permission view**

Confirm the prompt and command disclosure controls, the outer fixed frame, and the current `ScrollView` sizing modifiers. Keep the existing command expansion behavior unchanged.

**Step 2: Implement the smallest UI change**

Show the prompt `Show more`/`Show less` control only when the full user prompt exceeds the prompt preview limit (including multiline content that actually overflows that limit). Keep short one-line and short multiline prompts fully visible without a disclosure control.

Move the fixed `minHeight`/`maxHeight` viewport frame outside the scroll content and apply scrolling only to the inner details stack. Do not derive the outer frame from the expanded content’s measured height.

**Step 3: Build the Debug target**

Run the project’s Debug build command and confirm it succeeds without changing the installed application.

### Task 2: Preserve the native Codex permission prompt alongside the notch mirror

**Files:**
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Modify: `boringNotch/features/CodexNotifications/CodexPermissionRelay.swift` only if relay response handling needs a focused correction

**Step 1: Verify the generated hook contract**

The `PermissionRequest` hook is configured as an asynchronous command. It opens the notch mirror immediately and keeps a loopback callback alive for the notch action, while Codex continues to its normal approval prompt. The callback metadata identifies the Accessibility control path; the hook’s output is informational because background hooks cannot control the triggering operation.

**Step 2: Fix the lifecycle race**

Ensure the hook opens the notch before waiting, does not dismiss the SwiftUI notification merely because the native prompt is still pending, and sends `PostToolUse` after a native Allow. A notch decision presses the native Codex control first, then releases the callback waiter; an unavailable Accessibility path leaves the notification visible and opens Codex for manual response.

**Step 3: Add regression coverage**

Verify the Swift state parses the accessibility callback metadata, retains the permission notification until a tool completion, and removes the matching request on `PostToolUse`.

### Task 3: Verify and reset the Debug app for manual testing

**Files:**
- No installed-app files; use only the Debug derived-data product.

**Step 1: Run focused tests**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
swift test --filter CodexNotificationsCoreTests \
  --scratch-path /tmp/boring-notch-swiftpm-cache
```

Expected: all selected tests pass.

**Step 2: Rebuild and relaunch Debug**

Build with the existing `xcodebuild` Debug command, quit other `boringNotch` processes, and open only:

`/Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications/Build/Products/Debug/boringNotch.app`

Use Debug Settings once to reinstall the generated hook after any helper-script change.

**Step 3: Manual checks**

Verify a short prompt has no prompt disclosure control, a long prompt can expand, scrolling does not resize the expanded notch, and a permission request is visible in Codex and the notch simultaneously. Verify Allow/Deny from the notch dismisses the notch after the relay response while Codex reflects the same decision.
