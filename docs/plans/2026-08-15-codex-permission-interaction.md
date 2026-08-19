# Codex Permission Prompt Interaction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep expanded permission prompts stable while scrolling, allow direct notch decisions, expose full commands on demand, and make passive prompt dismissal restart cleanly around hover.

**Architecture:** The Debug app will install a synchronous Codex `PermissionRequest` hook that publishes a short-lived localhost decision callback in the notch payload and returns Codex’s official allow/deny hook response. The SwiftUI permission surface will use a fixed viewport with an expandable command section, while the notification manager owns a cancellable three-second passive dismissal timer that is cancelled on hover and restarted on pointer exit.

**Tech Stack:** Swift 5.10, SwiftUI, Foundation, Python 3 hook script, XCTest, Xcode Debug build.

---

### Task 1: Install an authoritative PermissionRequest hook

**Files:**
- Modify: `boring.notch/BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Modify: `boring.notch/boringNotch/components/Settings/Views/CodexNotificationSettingsView.swift`

Replace the async-only PermissionRequest script with a synchronous localhost callback server. Include `boring_notch_approval` metadata (`port`, random token, and expiry) in the event sent to the notch, accept exactly one token-checked `allow` or `deny` POST, return the official Codex hook decision JSON, and return `{}` on timeout so Codex can show its normal prompt. Use a 75-second PermissionRequest timeout and five-second fire-and-forget timeouts for UserPromptSubmit/Stop; do not mark any Boring Notch handler async. Update the settings copy to explain direct notch decisions and timeout fallback.

Validate the generated script with `python3 -m py_compile` after exporting it through the app’s Connect/update action, and verify the resulting `hooks.json` has the expected timeout/async shape.

### Task 2: Stabilize the expanded permission viewport

**Files:**
- Modify: `boring.notch/boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`
- Modify: `boring.notch/boringNotch/components/Notch/OpenNotchContentView.swift` if the host needs an explicit permission content height.

Give the permission scroll region a fixed height derived from the existing open-notch size, aligned to the top. Keep its contents scrollable without allowing the outer notch window to remeasure when the command expands or the user scrolls.

### Task 3: Add command disclosure and direct decision controls

**Files:**
- Modify: `boring.notch/boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`

Show a two-line command preview that SwiftUI truncates with `...`, add a `Show more`/`Show less` control for long or multiline commands, and render the full command when expanded inside the fixed scroll viewport. Keep the existing Allow/Deny buttons wired to the callback relay and remove the Open Codex-only state for newly installed callbacks; retain a clear fallback if an old/expired event has no callback metadata.

### Task 4: Reset passive dismissal around hover

**Files:**
- Modify: `boring.notch/boringNotch/features/CodexNotifications/CodexNotificationManager.swift`
- Modify: `boring.notch/boringNotch/features/CodexNotifications/CodexNotificationExtension.swift`

Cancel the passive timer whenever the pointer enters the prompt. On pointer exit, start a fresh three-second timer; if the pointer re-enters, cancel that timer again. Preserve the opening/closing animation duration outside the visible three-second dwell and clear state only after the close transition completes.

### Task 5: Test, rebuild, reinstall Debug hooks, and reset the app

Run the focused SwiftPM tests, `git diff --check`, and the Debug Xcode build with the project’s existing module-cache overrides. Quit all other `boringNotch` processes, open only `/Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications/Build/Products/Debug/boringNotch.app`, and use its settings action once to install the new hook into the user Codex configuration. Manually verify success/failure/permission events, stable scrolling, command expansion, direct Allow/Deny dismissal, and hover timer reset.
