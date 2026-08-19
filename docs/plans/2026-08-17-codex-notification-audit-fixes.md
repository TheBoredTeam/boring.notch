# Codex Notification Audit Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Codex notch notifications fail closed, resource-bounded, testable in CI, and focused enough for a future contribution to `dev`.

**Architecture:** The Codex hook signs a bounded JSON payload with a per-install secret owned by the unsandboxed helper. The app asks the helper to validate the signature and timestamp before parsing or displaying the event. Accessibility decisions require an exact request match and never fall back to an unrelated single prompt.

**Tech Stack:** Swift 5, SwiftUI, AppKit Accessibility APIs, CryptoKit, Python 3 standard library, Swift Package Manager, GitHub Actions.

---

### Task 1: Synchronize the feature base

**Files:**
- No source files.

**Step 1:** Fetch `upstream/dev` and confirm the live base.

**Step 2:** Rebase the feature branch onto the current `upstream/dev` without modifying user-owned untracked files.

**Step 3:** Verify the branch remains configured to push only to `origin/feature/codex-notification`.

### Task 2: Make permission matching fail closed

**Files:**
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Test: `boringNotchTests/CodexNotificationsCoreTests.swift`

**Step 1:** Remove single-prompt fallback collections and parameters from the Accessibility matcher.

**Step 2:** Require normalized request text to be contained in the candidate prompt text; remove fuzzy token-overlap matching.

**Step 3:** Ensure both status polling and Allow/Deny execution use the same exact matcher.

**Step 4:** Build the helper target and expect success.

### Task 3: Authenticate and bound hook events

**Files:**
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift`
- Modify: `boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift`
- Modify: `boringNotch/XPCHelperClient/XPCHelperClient.swift`
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Modify: `boringNotch/boringNotchApp.swift`

**Step 1:** Add a helper API that verifies an HMAC-SHA256 signature over the encoded payload and rejects timestamps outside a short clock-skew window.

**Step 2:** Generate a 32-byte per-install secret with mode `0600`; write the script and secret before enabling hooks in `hooks.json`.

**Step 3:** Update the Python hook to add signed timestamp/nonce metadata, bound prompts and tool input below the Swift parser limit, and include a signature query item.

**Step 4:** Make URL handling asynchronous and parse events only after helper verification succeeds.

**Step 5:** Reject unsigned, stale, malformed, disconnected, and oversized events.

### Task 4: Bound lifecycle and simplify state

**Files:**
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Modify: `boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`
- Modify: `boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Test: `boringNotchTests/CodexNotificationsCoreTests.swift`

**Step 1:** Remove the detached six-hour transcript watcher from the installed script.

**Step 2:** Stop native prompt polling if the expected prompt never appears within ten seconds.

**Step 3:** Remove the unused `expiresAt`, expiration task, and synthetic expiration test paths.

**Step 4:** Add regression tests for payload size rejection and negated failure phrases.

**Step 5:** Run the core tests and expect all tests to pass.

### Task 5: Remove unrelated behavior and harden modular boundaries

**Files:**
- Modify: `boringNotch/boringNotchApp.swift`
- Modify: `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift`
- Modify: `boringNotch/private/CGSSpace.swift`
- Modify: `boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift`

**Step 1:** Remove active-Space observation, forced `orderFrontRegardless`, and private CGS refresh code introduced by this feature.

**Step 2:** Replace ambiguous notification correlation strings with an unambiguous length-prefixed identifier.

**Step 3:** Keep the open notch refactor dependency isolated and document it in the final handoff rather than adding more unrelated compatibility code.

### Task 6: Commit and run tests in CI

**Files:**
- Add: `Package.swift`
- Modify: `.github/workflows/cicd.yml`

**Step 1:** Commit the existing minimal Swift package that exposes only the Codex core and its tests.

**Step 2:** Add a GitHub Actions test step before the app build.

**Step 3:** Run `swift test`, `git diff --check`, and a Debug app build; expect success.

**Step 4:** Review the final diff against `upstream/dev`, confirm no translation files changed, and confirm user-owned untracked files remain untouched.

**Step 5:** Create concise commits, push only `feature/codex-notification` to `origin`, and do not create an issue or pull request.
