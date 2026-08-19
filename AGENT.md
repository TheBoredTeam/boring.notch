# Codex Notification Manual Test Workflow

Use these tests from a normal Codex daily-work conversation. Do not use a synthetic `boringnotch://` URL for product validation: the goal is to exercise the real Codex hook lifecycle.

## Preconditions

1. After every source modification, quit all existing Boring Notch instances and any older Debug helper processes before testing. Never reuse an older running process.
2. Build and open only the newest Debug app:

   `/Users/paradox/Library/Developer/Xcode/DerivedData/boring-notch-codex-notifications/Build/Products/Debug/boringNotch.app`

3. If the hook template or hook configuration changed, remind the user to open the Debug app’s Codex settings and click `Connect or update Codex`, then restart Codex and re-trust the updated hooks when prompted. Do not treat the runtime as updated until this is complete. Otherwise, confirm the existing hook connection before testing.
4. Start each case in a new Codex conversation in the project workspace. Finish or resolve the previous case before starting the next one.
5. Keep the pointer away from the notch while checking the normal three-second timeout. Hover only when testing the expanded or hover-pause behavior.
6. If the source changed, run the focused tests before testing manually:

   ```bash
   cd "/Users/paradox/Documents/Boring Notch Contribution/boring.notch"
   CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
   SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
   swift test --filter CodexNotificationsCoreTests \
     --scratch-path /tmp/boring-notch-swiftpm-cache
   ```

## Case 1 — successful instruction

Paste this prompt into a new Codex conversation:

```text
In the current project, run this harmless workspace-only check:

printf 'case1-success\n'

Verify that the command exits with status 0, then reply exactly:
Case 1 success complete.

Do not ask for permission, retry the command, or cancel the task.
```

Expected result:

- After the conversation completes, the closed notch shows the green Success style only.
- The first line is the shortened user instruction; the second line is `Success · <project>`.
- The prompt uses the normal open/close animation and remains visible for about three seconds when it is not hovered.
- Hovering before the timeout holds the prompt open. Move the pointer away to allow the close animation.
- No grey Finished/completed variant should appear.

## Case 2 — interrupted or dropped instruction

Use a controlled interruption instead of deliberately exhausting credits or disrupting the network. Paste this prompt into a new Codex conversation:

```text
Run `sleep 120` in the foreground as the only task and leave it running.
Do not retry, replace, or terminate it yourself. I will press the Codex
Stop/Cancel control after the command is visibly running.
```

Test steps:

1. Wait until the `sleep 120` command is visibly running.
2. Press Codex Stop/Cancel. Do not press Ctrl-C in a separate terminal; the test needs the Codex turn to be interrupted.
3. Move the pointer away from the notch and observe the result.

Expected result:

- The notch shows the red Failure style with `Failure · <project>`.
- The interrupted turn produces one failure notification; it must not remain stuck forever.
- The failure prompt follows the same approximately three-second unhovered timeout and hover pause as Case 1.
- A real network failure or credit exhaustion can be used as an additional variation, but the controlled Stop test is the deterministic baseline.

## Case 3 — permission required

Run this case with Codex set to **Ask for approval**. In **Approve for me** mode,
the same request must not create a Boring Notch permission prompt because Codex's
automatic reviewer owns the decision.

Use a safe file operation outside the current workspace so Codex must request approval. Paste this prompt into a new Codex conversation:

```text
Run exactly one shell command for this whole test. Set a cleanup trap before
the write, create `~/Desktop/codex-notification-permission-test.txt` with the
exact contents `case3-permission`, read it back, explicitly delete it, and
verify that the path no longer exists. The target is deliberately outside the
current workspace: ask me for permission before executing the write, and do
not choose another location or skip the write. After an Allow decision,
always complete the cleanup before reporting the test complete, including if
the read-back step fails.
```

Test steps:

1. Wait for the orange Boring Notch permission prompt. In Ask for approval mode,
   it is the first and only prompt; the native Codex prompt appears only after
   choosing Review in Codex.
2. Verify the compact notch prompt is orange and says `Permission Required · <project>`.
3. Hover over the compact prompt to open the expanded permission view.
4. Verify the expanded view uses a vertical details/actions layout. The full
   request details remain in the bounded scroll area, and Allow/Deny remain
   visible without scrolling. Review in Codex is a plain text action in the
   upper-right corner, not a button in the action group.
5. Move the pointer away without choosing. The expanded view must collapse back to the orange compact prompt and remain available.
6. Run the test three times with fresh conversations:
   - Choose Allow in the expanded notch. The single command should run, read
     back `case3-permission`, delete the file, verify that the path is absent,
     and close the permission prompt.
   - Choose Deny in the expanded notch. The command should not run, and the
     permission prompt should close after Codex records the denial.
   - Choose Review in Codex. The notch prompt should close before the native
     Codex prompt appears; choose a decision there and verify the command is
     handled by Codex.
7. Confirm `~/Desktop/codex-notification-permission-test.txt` is absent after the Allow run. If the task was interrupted before cleanup, remove the file manually before repeating the case.

Expected result:

- In Ask for approval mode, Boring Notch is the active permission authority.
  The native Codex prompt appears only after the explicit Review in Codex handoff.
- Clicking the compact notch prompt expands the notch details.
- Moving the pointer away collapses the expanded view back to the compact notch prompt without dismissing it.
- A successful Allow or Deny decision closes the matching notch request. It must not leave a stale permission prompt behind.
- Review in Codex is unstyled text at the expanded view's upper-right corner;
  it closes the notch before handing the unresolved request to Codex.

### Approve for me variation

Repeat the same outside-workspace request with **Approve for me** enabled.

- No permission request appears in Boring Notch.
- Codex's automatic reviewer handles the request without leaving a stale orange prompt.

## Between-case reset

- Resolve any active permission request before starting another case.
- Move the pointer off the notch and wait for passive Success/Failure notices to close.
- If a stale prompt remains, quit and reopen only the Debug app at the path above, then restart the Codex conversation. Do not launch the removed `/Applications/boringNotch.app` copy.

## Troubleshooting

- No Success or Failure prompt: the shell command was probably run directly from a terminal. Only a command executed inside a Codex conversation produces the Codex lifecycle hooks. Confirm the Debug hook is installed and trusted, then restart Codex.
- No Failure after Stop: confirm `sleep 120` was running before pressing Codex Stop/Cancel. Do not interrupt it from another terminal.
- No notch permission prompt: reconnect/restart Codex and reinstall the hook
  from the Debug app’s Codex settings. Confirm the thread is using Ask for
  approval; Approve for me and an unknown reviewer intentionally produce no
  notch prompt.
- Allow/Deny cannot reach Codex: check that the card is still inside its
  callback window and inspect the app/helper logs for the readiness handshake.
  Codex permission decisions do not require Accessibility access or a native
  prompt matcher.
- Duplicate prompts or unexpected layout: close stale Boring Notch processes and verify that only the DerivedData Debug bundle is running.
- Choice shown as Success: inspect the Stop event's `last_assistant_message`; the
  classifier must recognize explicit choice language before any reported success
  status. Run `testDecisionMessageOutranksReportedSuccessStatus` before a manual
  retest.

## Confirmed root causes and debug reference (2026-08-18)

- **The “selected Codex permission prompt could not be matched” error was an
  architectural failure.** Codex renders its permission UI in a separate
  renderer that does not expose the expected controls in the Accessibility tree.
  Trying to locate and click a native prompt was therefore inherently racy and
  could not reliably send a decision. The current design has one authority:
  the PermissionRequest hook waits on a token-authenticated local callback;
  Allow/Deny answer that callback, while Review in Codex closes the notch first
  and then hands the unresolved request to Codex.
- **A changed hook can be silently skipped until it is trusted again.** Codex
  fingerprints each installed hook. The persisted PermissionRequest trust hash
  still described the old `timeout: 5` handler while the installed handler used
  `timeout: 75`, so Codex omitted PermissionRequest even though the other hooks
  continued to run. After any hook-template/configuration change, use Connect or
  update Codex, restart Codex, and re-trust the updated hook.
- **Reviewer mode is not the same field as hook `permission_mode`.** The stable
  PermissionRequest payload does not identify the desktop automatic reviewer.
  The hook reads the per-thread `approvalsReviewer` state instead: only `user`
  opens the notch; `auto_review` and unknown state return `{}` so Approve for me
  never shows a stale prompt.
- **Delivery must be acknowledged before waiting for a decision.** The hook
  exposes a one-shot local callback, the app sends `ready` after authenticating
  and accepting the event, and the hook falls back to Codex after five seconds
  without that acknowledgement. A delivered request then has a 60-second
  decision window; Allow, Deny, or Review in Codex consumes it exactly once.
- **The compact and expanded layouts are different surfaces.** The closed
  prompt follows the established vertical stack: a clear notch row followed
  by the 236-point summary row shown under the notch. Keep those rows finite
  so the summary is not clipped; the expanded permission view is a separate
  vertical, fixed-height viewport with its own scroll region.
- **Two simultaneously actionable approval windows are not supported by the
  current Codex hook contract.** Codex runs `PermissionRequest` hooks before it
  opens the native approval request, and the hook output is the only supported
  decision channel. Holding the hook open is what lets Notch Allow/Deny answer
  Codex; returning `{}` is what lets the native prompt appear, but leaves no
  supported channel for a later Notch decision. There is currently no
  `defer_to_native` response or post-decision hook. Do not restore Accessibility
  prompt matching to fake a dual-authority flow: that is the source of the
  original “selected Codex permission prompt could not be matched” failure.
- **A Stop payload can report success while its assistant message asks for a
  choice.** Classifying `status: "succeeded"` before inspecting
  `last_assistant_message` turns those turns into a green Success notice. Keep
  failure precedence, but classify explicit manual/decision language first so
  questions such as “please choose…” produce the purple Decision Required
  notice.

## Result checklist

| Case | Trigger | Expected status | Expected color | Dismissal |
| --- | --- | --- | --- | --- |
| 1 | Normal successful completion | Success | Green | About 3 seconds unless hovered |
| 2 | Codex turn stopped while `sleep` runs | Failure | Red | About 3 seconds unless hovered |
| 3 | Write outside workspace | Permission Required | Orange | Allow/Deny or Codex completion |
| 4 | Stop message asks the user to choose | Decision Required | Purple | About 3 seconds unless hovered |
