# Notch Codex Approvals Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let a user approve or deny a live Codex permission request from the Boring Notch prompt, while all non-permission results behave as brief, auto-dismissing notifications.

**Architecture:** The synchronous \`PermissionRequest\` hook starts a one-request HTTP listener bound only to \`127.0.0.1\`, includes its random one-time token and port in the existing Boring Notch URL event, and waits up to 60 seconds. The sandboxed Boring Notch app presents the request, posts the selected decision back to that loopback listener, and the hook emits the documented Codex structured \`allow\` or \`deny\` response. A timeout, connection failure, malformed callback, or app absence emits \`{}\` so Codex displays its native approval UI.

**Tech Stack:** Swift 5.10, SwiftUI, Foundation \`URLSession\`, Python 3 standard library (\`http.server\`), XPC helper, XCTest, Xcode.

---

## Product and safety decisions

- Only direct Codex \`PermissionRequest\` events are actionable in the notch. The prompt remains visible until the user presses **Allow** or **Deny**.
- Hovering an actionable prompt replaces its passive summary with two explicit buttons. The user must click one; the outer notification must not turn a hover or ordinary click into an approval.
- Success and failure notices are passive and auto-dismiss after 3 seconds. Finished, decision-needed, and manual-check notices auto-dismiss after 12 seconds. All retain click-to-open-Codex behaviour.
- The hook allows or denies exactly one request. It accepts callbacks only at \`127.0.0.1\`, validates a 32-byte random token with a constant-time comparison, and exits after 60 seconds. There is no persistent socket, saved approval, broad permission rule, or fallback Allow.
- Keep \`async\` absent from the \`PermissionRequest\` hook. This flow requires the hook process to stay synchronous until it receives the explicit user decision. Preserve other users’ hooks when rewriting \`hooks.json\`.

### Task 1: Add testable permission callback metadata and notification lifetimes

**Files:**

- Modify: \`boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift\`
- Modify: \`boringNotchTests/CodexNotificationsCoreTests.swift\`

**Step 1: Write the failing parser and lifetime tests**

Add tests that parse a \`PermissionRequest\` containing:

\`\`\`json
"boring_notch_approval": {
  "port": 49152,
  "token": "5d9WZp_2A7ZpScBMb2d7Osgih6g_sS6wAyoAwGSbrZ4"
}
\`\`\`

Assert that the visible notification contains the loopback callback metadata. Add tests that reject an absent, invalid-port, or short-token callback; only \`.needsAction(.permission)\` has a \`nil\` expiry; success and failure expire after 3 seconds, while decision, manual-check, and finished expire after 12 seconds.

**Step 2: Run the focused test target and verify it fails**

Run: \`swift test --filter CodexNotificationsCoreTests\`

Expected: FAIL because \`CodexPermissionCallback\`, callback parsing, and the revised persistence rule do not exist.

**Step 3: Implement the smallest data model**

Add these public, \`Equatable\`, \`Sendable\` values to the core module:

\`\`\`swift
public struct CodexPermissionCallback {
    public let port: Int
    public let token: String
}

public enum CodexPermissionDecision: String, Sendable {
    case allow
    case deny
}
\`\`\`

Extend \`.permissionRequest\` and \`CodexJobNotification\` with an optional callback. Parse only \`boring_notch_approval.port\` in \`1024...65535\` and an ASCII URL-safe token of at least 32 characters. Treat invalid metadata as no callback, never as an error that blocks ordinary Codex approval. Change \`CodexJobStatus.isPersistent\` so only \`.needsAction(.permission)\` is persistent; use 3-second expiry for success and failure and 12 seconds for other passive statuses.

**Step 4: Run the focused tests and verify they pass**

Run: \`swift test --filter CodexNotificationsCoreTests\`

Expected: all core tests pass, including callback validation and expiry behaviour.

**Step 5: Commit**

\`\`\`bash
git add boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift boringNotchTests/CodexNotificationsCoreTests.swift
git commit -m "feat: model Codex notch approval callbacks"
\`\`\`

### Task 2: Relay an explicit notch decision to the live hook

**Files:**

- Create: \`boringNotch/features/CodexNotifications/CodexPermissionRelay.swift\`
- Modify: \`boringNotch/features/CodexNotifications/CodexNotificationManager.swift\`

**Step 1: Write a failing relay validation test**

Extract endpoint construction into an internal helper and test that it creates only:

\`\`\`
http://127.0.0.1:<validated-port>/decision
\`\`\`

The helper must reject all other hosts and invalid ports before any request can be made.

**Step 2: Run the focused test target and verify it fails**

Run: \`swift test --filter CodexNotificationsCoreTests\`

Expected: FAIL because the endpoint helper does not exist.

**Step 3: Implement the loopback relay**

Implement \`CodexPermissionRelay.submit(_:callback:) async throws\` with a \`URLSession\` POST to \`/decision\`, \`Content-Type: application/json\`, and body:

\`\`\`json
{"token":"<one-time-token>","decision":"allow"}
\`\`\`

Use a 5-second request/resource timeout and accept only a 2xx HTTP response. In \`CodexNotificationManager\`, expose \`@Published private(set) var submittingNotificationIDs: Set<String>\` and an async \`submitPermissionDecision(_:for:)\`. It must require a permission notification with callback metadata, disable repeat submissions, dismiss only after a successful relay response, and retain the prompt plus an error message on failure.

**Step 4: Run tests and build**

Run: \`swift test --filter CodexNotificationsCoreTests\`

Run: \`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/boring-notch-codex-derived build\`

Expected: core tests pass and the Debug build succeeds.

**Step 5: Commit**

\`\`\`bash
git add boringNotch/features/CodexNotifications/CodexPermissionRelay.swift boringNotch/features/CodexNotifications/CodexNotificationManager.swift boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift boringNotchTests/CodexNotificationsCoreTests.swift
git commit -m "feat: relay notch permission decisions to Codex"
\`\`\`

### Task 3: Install a synchronous, one-time permission hook

**Files:**

- Modify: \`BoringNotchXPCHelper/BoringNotchXPCHelper.swift\`
- Modify: \`boringNotch/components/Settings/Views/CodexNotificationSettingsView.swift\`

**Step 1: Add installer assertions before modifying the generated script**

Test or manually inspect the generated configuration to ensure:

- \`PermissionRequest\` gets a 75-second command-hook timeout.
- \`UserPromptSubmit\` and \`Stop\` retain their 5-second notification timeout.
- all Boring Notch-owned groups are replaced, while unrelated hook groups remain intact.

**Step 2: Implement \`PermissionRequest\` handling in the generated Python script**

For permission events only, the script must:

1. Generate \`secrets.token_urlsafe(32)\`.
2. Start \`ThreadingHTTPServer(("127.0.0.1", 0), Handler)\` and set a short request poll timeout.
3. Add the listener’s port and token under \`boring_notch_approval\` in the URL payload.
4. Open \`boringnotch://codex-event?...\` as today.
5. Accept exactly one \`POST /decision\`; parse JSON; require a constant-time token match and \`allow\` or \`deny\`.
6. Print the official hook response:

\`\`\`json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
\`\`\`

or the matching \`deny\` response. On timeout/error, close the server and print \`{}\`.

For \`UserPromptSubmit\` and \`Stop\`, preserve today’s fire-and-forget URL notification plus \`{}\` output.

**Step 3: Require update when the owned generated script is stale**

Change \`isCodexNotificationHookInstalled\` to require the current generated-script contents and the correct owned groups. A user with the old notification-only script therefore sees **Update Codex connection** rather than a misleading connected state. Do not migrate or alter unrelated hooks.

**Step 4: Update Settings copy**

Replace the statement that Boring Notch “never answers permissions” with explicit disclosure: it can approve or deny only the request visibly shown in the notch after the user clicks a choice; a timeout leaves the normal Codex approval prompt available. Update the setup text to ask the user to reconnect/restart Codex and trust the updated hooks.

**Step 5: Build and inspect the generated artifact**

Run: \`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/boring-notch-codex-derived build\`

Manual check: connect the Debug app, inspect \`~/.codex/hooks.json\`, and verify the Boring Notch \`PermissionRequest\` group has timeout \`75\` and no \`async\` flag.

**Step 6: Commit**

\`\`\`bash
git add BoringNotchXPCHelper/BoringNotchXPCHelper.swift boringNotch/components/Settings/Views/CodexNotificationSettingsView.swift
git commit -m "feat: install one-time notch approval hook"
\`\`\`

### Task 4: Add the hover-to-decide notch prompt

**Files:**

- Modify: \`boringNotch/extensions/NotchExtensionRegistry.swift\`
- Modify: \`boringNotch/components/Notch/ClosedNotchRenderer.swift\`
- Modify: \`boringNotch/features/CodexNotifications/CodexNotificationExtension.swift\`

**Step 1: Make extension selection optional**

Change \`ClosedNotchExtensionActivity.onSelect\` to \`(() -> Void)?\`. In \`ClosedNotchRenderer\`, attach the outer tap gesture only when this callback is non-\`nil\`, so SwiftUI buttons inside an actionable notification receive their own clicks without triggering “open Codex.”

**Step 2: Implement the compact permission prompt**

Keep the existing daily-planning-derived vertical layout: a clear notch row followed by a 236-point prompt row. For a live permission callback:

- Normal state: show the lock icon, task title, and a one-line “Needs permission” summary.
- Hover state: retain the lock icon and replace summary content with \`Deny\` and green \`Allow\` buttons.
- Disable both buttons while the relay is in progress.
- \`Allow\` calls \`submitPermissionDecision(.allow, for:)\`; \`Deny\` calls \`.deny\`.
- Do not dismiss the prompt on hover, ordinary click, failed relay, or timeout. A successful relay removes it.

For every other status, show the passive prompt and preserve the optional tap-to-open-Codex behaviour. Success and failure disappear automatically after 3 seconds; other passive statuses disappear after 12 seconds.

**Step 3: Add accessibility labels**

Expose the task title and summary on the passive prompt. On hover, expose distinct \`Allow Codex permission\` and \`Deny Codex permission\` button labels. Mark decorative pulse/dot elements hidden.

**Step 4: Build**

Run: \`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/boring-notch-codex-derived build\`

Expected: \`BUILD SUCCEEDED\`.

**Step 5: Commit**

\`\`\`bash
git add boringNotch/extensions/NotchExtensionRegistry.swift boringNotch/components/Notch/ClosedNotchRenderer.swift boringNotch/features/CodexNotifications/CodexNotificationExtension.swift
git commit -m "feat: decide Codex permissions from notch hover prompt"
\`\`\`

### Task 5: End-to-end manual verification

**Files:**

- No production file changes expected.

**Step 1: Rebuild and open one Debug instance**

Run: \`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/boring-notch-codex-derived build\`

Open only \`/tmp/boring-notch-codex-derived/Build/Products/Debug/boringNotch.app\`; quit installed and other Debug copies to avoid overlapping notch windows.

**Step 2: Verify Allow**

Use a local Python fixture that behaves like the generated permission listener, emits a URL event with a token and port, then records its received decision. Hover the notch prompt, click **Allow**, and verify:

- the fixture received \`allow\` with the exact token;
- the notch prompt disappears;
- the fixture would emit Codex’s \`PermissionRequest\` \`allow\` JSON.

**Step 3: Verify Deny**

Repeat with a fresh fixture/token. Click **Deny** and verify \`deny\` arrives and the prompt disappears.

**Step 4: Verify safe failures**

Repeat without a listener and verify the prompt remains visible with a relay error. Let an active listener run past 60 seconds and verify the script outputs \`{}\` (normal Codex approval fallback), not \`allow\`.

**Step 5: Verify passive notifications**

Deliver synthetic \`Stop\` events for succeeded and failed outcomes. Verify they render as a brief daily-planning-style notification and disappear after 3 seconds without requiring a click.

**Step 6: Run full checks**

Run: \`swift test\`

Run: \`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/boring-notch-codex-derived build\`

Expected: all core tests pass and the Debug build succeeds.

**Step 7: Commit**

\`\`\`bash
git add -A
git commit -m "test: verify notch Codex approval flow"
\`\`\`
