# Codex Permission Authority Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reliably route user-reviewed Codex permission requests through Boring Notch, suppress auto-reviewed requests, and hand off to Codex without Accessibility matching when the user prefers the native prompt.

**Architecture:** A synchronous `PermissionRequest` hook is the sole decision authority while the notch card is active. It opens a token-authenticated one-shot listener on `127.0.0.1`, sends the callback metadata to Boring Notch, and returns Codex's documented allow/deny response; a third `codex` callback closes the notch and returns no decision so Codex then opens its native prompt. This avoids two independently actionable windows and removes the unsupported Accessibility bridge entirely.

**Tech Stack:** Swift 5.10, SwiftUI, URLSession, generated Python 3 hook, loopback HTTP, HMAC-SHA256 event authentication, XCTest.

---

### Task 1: Model one-shot hook callbacks

**Files:**
- Modify: `boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`
- Test: `boringNotchTests/CodexNotificationsCoreTests.swift`

**Step 1: Write the failing parser tests**

Add tests for valid callback metadata containing `port`, a URL-safe random `token`, and `expires_at`. Reject missing, expired, out-of-range, or malformed callback values. Keep the defensive `auto_review` reducer test.

**Step 2: Run the focused suite**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
swift test --filter CodexNotificationsCoreTests \
  --scratch-path /tmp/boring-notch-swiftpm-cache
```

Expected: the new callback tests fail before implementation.

**Step 3: Implement the minimal model**

Replace `CodexPermissionControl.accessibility` with a callback value object:

```swift
public struct CodexPermissionCallback: Equatable, Sendable {
    public let port: Int
    public let token: String
    public let expiresAt: Date
}
```

Store it on `CodexJobNotification`, parse only the current metadata shape, and present permission requests only when the callback is usable.

**Step 4: Re-run the focused suite**

Expected: all core tests pass.

### Task 2: Make the hook the permission authority

**Files:**
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Test: `boringNotchTests/CodexNotificationsCoreTests.swift`

**Step 1: Add generated-script assertions**

Assert that the generated script:

- creates a listener bound to `127.0.0.1` on an ephemeral port;
- authenticates callbacks with a one-time token;
- accepts only `allow`, `deny`, or `codex` once;
- emits documented `PermissionRequest` output for allow/deny and `{}` for `codex` or timeout;
- never opens a notch card for `auto_review`;
- configures `PermissionRequest` synchronously with a 75-second hook timeout.

**Step 2: Run the suite and confirm failure**

Expected: the script assertions fail against the Accessibility mirror.

**Step 3: Implement the generated Python broker**

The hook listens for at most 60 seconds. It opens the signed notch URL only after the listener exists, accepts a single authenticated POST, shuts down, and prints exactly one JSON result. Network or UI failure returns `{}` so Codex safely falls back to its own prompt.

**Step 4: Run the suite**

Expected: all script tests pass.

### Task 3: Submit decisions directly to the hook

**Files:**
- Create: `boringNotch/features/CodexNotifications/CodexPermissionRelay.swift`
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`

**Step 1: Implement the loopback relay**

Use an ephemeral `URLSession` with a five-second timeout. POST `{token, decision}` only to `http://127.0.0.1:<validated-port>/decision`; map connection loss and timeout to an expired-request error.

**Step 2: Replace manager submission**

Remove Accessibility authorization and prompt polling. For Allow/Deny, submit the callback and dismiss only after HTTP success. For “Review in Codex,” submit `codex`, dismiss the notch, then open the exact Codex task so the native prompt can appear.

**Step 3: Update the permission card**

Render `Deny`, `Review in Codex`, and `Allow`. Keep the card visible with a clear error if the one-shot callback fails.

### Task 4: Remove the obsolete Accessibility integration

**Files:**
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift`
- Modify: `boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift`
- Modify: `boringNotch/XPCHelperClient/XPCHelperClient.swift`
- Modify: `boringNotch/components/Settings/Views/CodexNotificationSettingsView.swift`

**Step 1: Delete AX permission APIs and implementation**

Remove all Codex AX tree traversal, matching, cached controls, renderer flags, decision posting, and diagnostics. Preserve the helper's general Accessibility functions because unrelated brightness/onboarding features still use them.

**Step 2: Correct Settings copy**

Explain that Boring Notch is the primary user-review surface and “Review in Codex” hands the unresolved request to the native Codex prompt. Remove the Codex-specific Accessibility section and rebuild warning.

### Task 5: Validate and install

**Files:**
- Verify: all changed files

**Step 1: Run focused tests and whitespace checks**

Run the Swift package tests and `git diff --check`.

Expected: PASS with no whitespace errors.

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

Expected: build succeeds, allowing existing unrelated warnings.

**Step 3: Install and manually verify**

Use `Connect or update Codex`, restart/re-trust hooks if Codex requests it, and verify:

- `Approve for me`: no notch permission card.
- `Ask for approval` + Allow/Deny in notch: Codex receives the decision and the notch closes.
- `Ask for approval` + Review in Codex: notch closes, native prompt opens, and Codex handles the decision.
- Existing passive Codex notices and unrelated notch features remain unchanged.
