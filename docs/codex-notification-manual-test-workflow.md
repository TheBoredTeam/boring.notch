# Codex notification manual test workflow

## Current notification contract

Notifications describe observable events. Stop with response text displays neutral **Response ready**; missing text displays **Codex update**. An explicit Interrupt displays **Stopped**. Only an authenticated, user-reviewed PermissionRequest with a live callback displays persistent orange **Permission Required**. Prose does not assert success, failure, or a required action. Review the response in Codex for those details.

## Build and connection

1. Run the Swift and embedded-hook tests from the feature checkout:

   ```sh
   CLANG_MODULE_CACHE_PATH=/tmp/boring-notch-clang-module-cache \
   SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boring-notch-swift-module-cache \
   swift test --filter CodexNotificationsCoreTests --scratch-path /tmp/boring-notch-swiftpm-cache
   python3 .github/scripts/test_codex_notification_hook.py
   python3 .github/scripts/evaluate_codex_notification_labels.py
   ```

2. Build a fresh Debug app:

   ```sh
   xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug \
     -derivedDataPath /tmp/boring-notch-codex-refinement build -quiet
   ```

3. Stop only stale Boring Notch processes and launch `/tmp/boring-notch-codex-refinement/Build/Products/Debug/boringNotch.app`. Do not reuse an earlier app or terminate unrelated applications.
4. The hook configuration now includes Interrupt with a three-second timeout. In the Debug app's Codex settings, reconnect/update Codex, restart Codex if needed, and review/trust the changed hooks. Do not treat the new runtime as validated until this is done. Existing connection controls may require disconnecting and then connecting again.
5. Use a new real Codex conversation for each case. Synthetic URLs only test rendering and are not substitutes for this matrix. Keep the pointer away until checking hover behavior.

## Real conversation cases

| Case | Action / prompt | Expected |
| --- | --- | --- |
| Response | Ask Codex to run `printf 'case1-success\n'` and report its exit status | One neutral Response ready notice; no success assertion |
| Ordinary phrase | Ask for the exact text “Implemented your choice and all tests passed.” | Response ready; no required-choice alert |
| Code example | Ask for a fenced example containing `error: file not found` | Response ready; no failure alert |
| Quoted checklist | Ask it to write “please test manually before release” as example checklist content | Response ready; no manual-check alert |
| Optional follow-up | Ask for a completed explanation ending with an optional offer of more examples | Response ready |
| Genuine prose question | Ask it to request an A/B choice and wait | Response ready; opening Codex shows the question. No automatic semantic action label is promised |
| Interrupted turn | Ask it to run only `sleep 120`, without retries; press Codex Stop after execution starts | One neutral Stopped notice from Interrupt; no Failure notice |
| Continue | Continue after a response and wait for another response | Prior passive notice clears; new response appears |
| Concurrent chats | Run two conversations, then interrupt one | Correct chat opens; other chat's permission/response is preserved |

Passive notices last about three seconds after entrance, pause on hover, and open the matching Codex chat when activated. Permission notices remain until a decision, expiry, or matching turn termination. Check compact and expanded text, camera clearance, animation, and accessibility labels in the newly built app.

Missing-message, conflicting undocumented status fields, long-response clipping, duplicate events, delayed Stop after Interrupt, and permission ordering are deterministic automated cases. They must not fabricate failure/success or resurface a dismissed interruption. Repeat delivery suppression retains the latest 100 correlated turn outcomes in memory; it is not durable history across restarts.

## Permission matrix

Use **Ask for approval**, then ask Codex to perform one harmless file write outside the workspace, read it back, delete it, and verify deletion. Set cleanup before the write. A suitable target is `~/Desktop/codex-notification-permission-test.txt`; do not overwrite an existing file. Resolve one test before starting another.

1. **Allow:** orange prompt appears; expand it; Allow runs the operation and cleanup; the matching prompt closes.
2. **Deny:** the operation does not run; matching prompt closes.
3. **Review in Codex:** the notch closes before handing control to the native approval UI; decide there.
4. **Approve for me:** repeat with automatic review enabled; no notch permission prompt appears.
5. **Concurrent requests:** independent pending requests remain correlated; ending one turn does not clear another turn's request.

The expanded view retains a bounded scroll area with visible Allow/Deny controls and a plain Review in Codex action. Pointer exit collapses to the persistent compact prompt. Verify the test file is absent after Allow or interrupted cleanup.

Never auto-trust hooks or modify stored trust fingerprints as a testing shortcut. If real Interrupt delivery is unavailable in the installed Codex version, record the version and block runtime acceptance; do not reintroduce transcript polling as a fallback.

## Research regression and interpretation

The evaluator compiles the baseline core at `9b62aefec74c9668dbf61a5a4a37e7091ddab7e0` and the working core, then sends the same synthetic Stop payloads through the real parser/reducer. Nine non-action cases include seven wording examples, missing text, and a clipped repair narrative. Four genuine action examples track the intentional loss of semantic classification; all should still produce a notification.

Do not present zero false alerts on this selected regression set as a measured production false-positive rate. This release removes ungrounded semantic alerts; it does not establish the proposed future semantic detector's precision/recall targets. Collect only explicitly selected, sanitized examples before evaluating such a detector. Do not log tokens, permission payloads, or private conversation text.

## Troubleshooting and historical causes

- No new behavior: verify the exact Debug bundle and current trusted hook definition. A changed hook fingerprint can cause Codex to skip it until reviewed and trusted again.
- No Stopped notice: verify Interrupt delivery on the installed Codex runtime. The old transcript watcher and synthetic failed Stop path have been removed.
- No permission prompt under automatic review is expected. Hook `permission_mode` does not identify the desktop approvals reviewer; only a user-reviewed request belongs in the notch approval flow.
- Historical Accessibility-based native permission matching failed because the renderer did not expose the required controls reliably. Preserve the token-authenticated callback and single decision authority; do not restore UI scraping.
- The delivery acknowledgement remains separate from the decision window. A late request for a terminated turn is handed back to Codex rather than acknowledged and left waiting invisibly.
- Historical phrase classification confused quoted instructions, examples, past failures, and actual requests. English negation patches did not address that distinction. Prefix clipping could remove the final repair explanation and flip the label. Lifecycle labels now ignore prose meaning, so clipping cannot alter them.
- Missing assistant text previously synthesized a failure narrative; unknown prose defaulted to Success. Both assertions have been removed.

## Acceptance record

Record the build path, Codex version, hook trust/update completion, and result of each real conversation case. Automated tests alone do not verify installed hook delivery or UI behavior.

### Automated refinement results — 2026-09-30

- Baseline: feature commit `9b62aefec74c9668dbf61a5a4a37e7091ddab7e0`.
- Selected non-action regressions: false alerts **9/9 → 0/9**.
- Total synthetic response notifications: **13/13 → 13/13**.
- Semantic blocking/manual-action detections: **2/4 → 0/4**. This is the deliberate neutral-label tradeoff, not a semantic recall improvement.
- 100 Swift tests and 7 embedded-hook tests passed; Debug build succeeded. The obsolete source-text assertion for bundle-ID routing was replaced by the executable exact-app-path check.
- Live connection and trust confirmed after reinstalling the routing fix. The response case reached the Debug process; the user saw its neutral grey speech-bubble icon but missed the label. The interruption case passed: Codex recorded an interrupted turn and the user confirmed Stopped. Live Allow, Deny, and Review in Codex subsequently passed in the primary chat; see the final permission acceptance record below.

Cause and correction: whole-response phrase matching, forced success/failure defaults, and prefix information loss produced unsupported labels. Primary status now comes only from the event and presence of response text; ambiguous content stays neutral. Interruption now uses Interrupt rather than a transcript watcher. Correlated terminal events remain deduplicated after dismissal, and uncorrelated Stop cannot clear another turn's permission.

Connection regression found during live setup: Interrupt was installed with timeout 3 while the helper's duplicate installation check expected 5, so Settings reported Not connected. Event names, trust names, and timeouts now share one definition; the same configuration module creates and validates handlers. Fresh-install recognition and rejection of the old incorrect timeout are covered by Swift tests. Interrupt is included in trust verification.

Live routing issue: launching the hook URL by shared bundle ID reopened the installed `/Applications` copy even while Debug was running. The hook now embeds the installing app's exact bundle path and uses `open -a` with that path. Reconnect and review/trust the updated hook after this change. Moving the app requires reconnecting. This avoids changing Launch Services defaults or modifying another app installation. The first attempted live response/interruption cases used the wrong bundle and are not counted as validation.

Live acceptance update: the installed hook now targets the exact rebuilt Debug bundle; all four hook definitions and trust entries verify as current. The user confirmed connection. A real response containing “Implemented your choice and all tests passed” reached the Debug process without launching the installed app; the user observed the neutral grey response icon, but the text label was not independently observed. In the same authorized temporary test chat, the user pressed Stop during the sleep case; Codex reported the turn as interrupted and the user confirmed the Stopped label. Live Allow/Deny/Review in Codex subsequently passed in the primary chat; see below. The earlier wrong-bundle run remains excluded from acceptance.

Permission acceptance attempt: after the user selected Ask for approval, the temporary test chat reported that its elevated temporary-file command was rejected because the effective Granular policy had `sandbox_approval: false`. The command did not execute and no test file was created. This is a policy block, not a human Deny result, and does not validate Allow/Deny/Review in Codex. This temporary-chat attempt remains excluded from acceptance; the primary-chat checks below supersede its blocked status.


### Final live permission acceptance — 2026-09-30

The temporary chat retained a policy that disallowed sandbox approval requests. After the primary chat permitted escalation, the same real permission cases were run here without bypassing the approval mechanism. This departs from the fresh-conversation-per-case procedure above; cases ran sequentially in the existing primary chat and each resolved before the next began.

- **Allow: passed.** The user confirmed the orange notch appeared and selected Allow. The command created a unique temporary Desktop file, verified its synthetic contents, deleted it, verified absence, and exited successfully.
- **Deny: passed.** The user selected Deny and confirmed the notice closed. The tool returned `PermissionRequest hook denied approval`; the shell command did not execute.
- **Review in Codex: passed.** The user confirmed selecting Review in Codex, then approving in Codex's native UI. The command ran successfully and removed its unique temporary file. Although the planned native decision was Deny, the observed native Allow validates the handoff and execution path. Notice closure timing before native UI was not independently observed.

Remaining live coverage: automatic-review suppression, concurrent permission requests and chats, the full wording/presentation matrix, and independent observation of the Response ready text label. Automated cases cover classification and ordering, but do not substitute for those live checks. No production false-positive or semantic recall target has been established. The implementation and the above live checks are complete; this record does not claim the entire manual matrix passed.

Visual refinement: passive icons and status text now use cyan; permission requests retain orange. The user confirmed the rebuilt cyan UI. PR images in `docs/images/codex-notifications/` are real captures of this Debug app rendered with synthetic context for privacy; they are UI previews, not additional live acceptance evidence.

Final palette: Response ready and Codex update use cyan; Stopped uses violet to distinguish interruption; Permission Required retains orange. Icons and text labels also distinguish states independently of color.
