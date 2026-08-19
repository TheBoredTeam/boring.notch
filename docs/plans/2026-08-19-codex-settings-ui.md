# Codex Settings UI Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Simplify the Codex settings screen, use the Codex app icon, explain each notification type briefly, and surface whether Codex has trusted every Boring Notch hook.

**Architecture:** Keep the settings screen declarative and let the existing unsandboxed XPC helper inspect Codex's hook configuration. The helper will report installation and trust separately; the view will poll while open and offer a deep link to Codex's hooks settings when trust is incomplete.

**Tech Stack:** SwiftUI, AppKit/NSWorkspace, NSXPC, Codex `hooks.json` and `config.toml` state.

---

### Task 1: Add hook trust status to the XPC boundary

**Files:**
- Modify: `boring.notch/BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift`
- Modify: `boring.notch/boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift`
- Modify: `boring.notch/BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
- Modify: `boring.notch/boringNotch/XPCHelperClient/XPCHelperClient.swift`

**Steps:**
1. Add an XPC method that returns whether all four Boring Notch hook entries (`permission_request`, `user_prompt_submit`, `post_tool_use`, and `stop`) have non-empty SHA-256 trust records in the Codex `config.toml` `[hooks.state]` sections.
2. Read the config from the same `.codex` home used by the helper; return `false` for missing, malformed, or incomplete state.
3. Add the async client wrapper with the same retry/error behavior as the existing hook-installation query.

### Task 2: Update the Codex settings presentation

**Files:**
- Modify: `boring.notch/boringNotch/components/Settings/SettingsView.swift`
- Modify: `boring.notch/boringNotch/components/Settings/Views/CodexNotificationSettingsView.swift`

**Steps:**
1. Replace the Codex sidebar bell symbol with the installed Codex/ChatGPT application icon via `NSWorkspace`, with an SF Symbol fallback if the app is unavailable.
2. Remove the explanatory footer under “Codex task notifications” and the passive-lifecycle footer under the notification list.
3. Replace “What appears in the notch” with a compact menu describing Working, Success, Failure, Permission, Decision, and Manual review notifications.
4. Remove “After connecting or updating”.
5. Add a hook-status row immediately below the Connect/Disconnect button. Show a green trusted state when all hooks are trusted; otherwise show an attention state and a “Trust hooks in Codex” button.
6. Open `codex://settings/hooks` from that button and refresh the status while the settings view is visible.

### Task 3: Build and verify

**Commands:**

```bash
git -C boring.notch diff --check
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
xcodebuild -project boring.notch/boringNotch.xcodeproj -scheme boringNotch \
  -configuration Debug \
  -derivedDataPath /Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications \
  build -quiet
CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
swift test --filter CodexNotificationsCoreTests \
  --scratch-path /tmp/boring-notch-swiftpm-cache
```

**Expected:** No diff-check errors, a successful Debug build, and all Codex core tests passing. Manual UI verification should show the Codex icon, no guide footers, the six-row notification menu, and a hook trust row that changes after trusting hooks in Codex.
