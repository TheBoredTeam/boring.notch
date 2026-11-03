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

Passive notices last about three seconds after entrance and pause on hover. Response ready notices with text expand on hover or activation; Open in Codex in the expanded card opens the matching chat. Other passive notices retain their direct-open behavior. Permission notices remain until a decision, expiry, or matching turn termination. Check compact and expanded text, camera clearance, animation, and accessibility labels in the newly built app.

## Response preview cases

Reconnect using the freshly built Debug app, then review/trust the updated hook before counting any live results. The hook now retains up to **16,000 Unicode code points** of the final Stop message. Exactly-at-limit text is complete. If the source or delivery budget requires shortening it, the preview retains the prefix and shows `...` outside the Markdown rendering, including after an incomplete code block or table. Serialized payloads remain bounded to 256 KiB; the complete signed Stop delivery URL is additionally bounded to 128 KiB. Other event types retain their existing transport behavior. Response text remains in memory; replay suppression stores a digest rather than the message-bearing payload.

The response card uses the permission card's width and camera clearance. Short replies fit their rendered content. Longer replies reach a maximum height approximately 60 points taller than the permission card and then scroll vertically. Tables and code can scroll horizontally within the body. Open in Codex stays outside the scrolling region. No image or other remote content loads automatically; ordinary web/email links require explicit activation. MarkdownUI 2.4.1 supplies GFM rendering on macOS 14; its maintenance-mode status is an accepted dependency tradeoff for the smaller static renderer without new executable build macros. SwiftMath at pinned revision `0b0222e102ba415b352cd29f334075622bd4e6aa` supplies local native LaTeX typesetting, including bold Greek symbols and custom operator names. The footer shows the matching chat title, shortened to one line when necessary, with the full title available on hover. Runtime dependency notices are retained in `THIRD_PARTY_LICENSES`.

The quick-reply implementation increases only the response card's maximum by another 68 points to accommodate its composer and the eight-point separation above it. Normal-notch and permission-card sizes retain their existing values. The one-to-three-line input, delivery feedback and Open in Codex stay outside the independently scrolling response. The chat title appears only in the footer; the duplicate reply caption and close cross were removed at the user’s request.

### Quick reply cases

The composer uses 11-point system text and starts with a 34-point input border. Clicking enables native editing; showing the card alone does not request focus. Return submits; Shift-Return adds a line; Return that confirms marked IME text must not submit. Whitespace-only drafts and repeated sends are ignored. Escape collapses without clearing a draft; Clear an editable draft by selecting and deleting its text; there is no caption/action row beneath the normal input. Uncertain-delivery feedback retains its explicit discard action. Drafts remain in memory and are bound to their originating prompt. Leaving the response window starts a two-second inactivity timer, even with keyboard focus, a draft or a pending/accepted send. Keyboard activity outside renews that timer; returning the pointer cancels it. Folding preserves the draft while the compact prompt remains available. Its normal three-second unhovered timeout then clears the matching draft and feedback. Explicit prompt dismissal or successful Open in Codex also ends that draft’s lifetime. Other responses wait while the originating prompt is retained; authenticated permission requests still preempt it.

The sandboxed app sends a typed reply request through its existing XPC connection. The containing-app-restricted, unsandboxed helper runs the CLI bundled with the official Codex app. The CLI transport is compiled only into the helper; the UI shares only its delivery-result enum. Lost XPC connections return uncertain delivery without an automatic retry. Before queueing, a metadata-only app-server connection verifies the session UUID against the exact root thread and confirms the originating turn among its 100 most recent turns, without loading message items. A shared-session/fork/subagent identity that cannot be proved exact fails safely and keeps its draft. This implementation does not guess a fork destination. It does not start a turn through the metadata connection or override the chat's model, working directory, permissions or environment.

Submission uses `codex queue --thread <verified-uuid> --message <text> --resume`, as documented in [Developer commands](https://learn.chatgpt.com/docs/developer-commands). The queue currently accepts message text through argv; the app does not log arguments or CLI output, but operating-system process inspection can see the argument while the short-lived CLI runs. Native UTF-8 process arguments preserve quotes, newlines and Unicode without invoking a shell. Output is bounded to 1 MiB, and each child has a 20-second deadline. Drafts and responses are never written to app storage; intentional submission transfers the message to Codex's own queue/history.

A positive queue acknowledgement clears only its matching draft. The rounded input retracts into the send-arrow position, shows a loading ring during delivery and then the original filled green check-circle on receipt. There is no success caption or waiting input placeholder. One accepted reply is allowed for each response notice; its composer stays read-only until a fresh authenticated response arrives, or the old prompt expires. Moving outside still folds the window after two idle seconds and starts the normal compact expiry. If queueing succeeded but resume warned, the card shows the green received check with the resume caveat in its tooltip/accessibility label, while Open in Codex remains available in the footer; it never queues the message again. Already-loaded desktop chats can consume the queue even with that warning, as observed below. Their next authenticated response releases the old card and presents a fresh latest-response notice. An uncertain outcome retains the original draft and disables resend until the user checks Codex and explicitly discards it. A failure before submission keeps the draft editable with Retry.

| Case | Action | Expected |
| --- | --- | --- |
| Native entry | Expand a real response, click input, type/paste/select text | One-click editing; hovering alone does not take focus |
| Keyboard / IME | Return, Shift-Return, marked-text confirmation, Escape | Submit, newline, composition confirmation without submit, and collapse with draft retained |
| Growing input | Enter more than three lines and scroll | Input stops growing at three lines; response and pinned footer remain usable |
| Fold / reopen / expiry | Type, move/click outside, reopen before expiry, then leave it untouched | Fold after two idle seconds; draft returns before compact expiry; expiry removes the draft |
| Two chats | Start a draft in A while B responds | Draft and send destination remain A; B waits |
| Permission preemption | Trigger a real approval while composing | Existing Allow/Deny/Review work; original draft survives and returns to its chat |
| Idle / busy send | Submit to an idle chat and one that became busy | Exact existing chat receives it; active task completes before the queued reply, without steering or interruption |
| Acknowledgement / expiry ordering | Receive the next hook or acknowledgement before/after expiry | Only the matching old notice/draft clears; expired drafts never return; newer replies survive late callbacks |
| Resume warning | Queue to an unloaded/unresumable chat | Queue acknowledged honestly; Open in Codex available; no duplicate queue operation |
| Failure / uncertain | Missing CLI, unprovable destination, failed launch, abnormal queue exit or timeout | Draft retained; Retry only when submission is known not to have happened; uncertain delivery requires checking Codex |
| Accessibility / displays | VoiceOver, long chat title, camera clearance, small screen, two displays | Caption/actions reachable; composer stays inside the bounded card; correct focus/hover ownership |

### Boxed math and response/composer spacing — 2026-11-03

- **Cause:** iosMath 2.5.0 supports the equation's wide hat, text, Greek letters and conditional notation, but rejects a whole-expression `\boxed{...}` command. The existing unsupported-expression path consequently displayed its LaTeX source.
- **Correction:** recognize a balanced, whole-expression box wrapper, typeset its contents through iosMath, and draw the surrounding frame locally. Nested groups, escaped braces and whitespace are handled; malformed and otherwise unsupported expressions retain the existing readable-source behavior. No new dependencies or copied third-party source were introduced.
- **Spacing:** add eight points above the composer and increase the response-only height cap by eight points, preserving the response viewport while moving the input and footer lower. The regular notch and permission card retain their dimensions.
- **Verification:** all 144 focused Swift tests passed, including two new boxed-equation regression cases and the native card/composer sizing checks. The synthetic boxed-loss glyph image and complete card capture were visually inspected. The Debug build passed. These results cover local rendering; the user's actual live equation and pointer/accessibility acceptance remain unverified. Hook/configuration files were not changed.
- **Motion proposal:** the separate HTML prototype at `sketches/codex-quick-reply/index.html` in the primary project demonstrates input roll into the right-hand submit icon, loading and a green receipt tick, plus draft restoration on failure. Normal, reduced-motion and narrow-browser behavior were checked. The user subsequently approved the motion and requested a pill-shaped bar and the original success icon; native integration is recorded below.

### Math command coverage and continuous send motion — 2026-11-03

- **Math cause:** the Gaussian distribution screenshot uses `\boldsymbol` and `\operatorname`, which iosMath 2.5.0 rejects. A focused reproduction confirmed each independently; the normal distribution, calligraphic letter and delimiters render without those commands. The earlier boxed-expression fix addressed a separate unsupported wrapper.
- **Math correction:** replace iosMath with the native SwiftMath renderer in both SwiftPM and Xcode. The required commands are supported by the reviewed upstream revision `0b0222e102ba415b352cd29f334075622bd4e6aa`; the older tagged 1.7.3 release lacks them, so the dependency is pinned to that exact revision rather than tracking a branch. Both lockfiles agree. No source-rewriting aliases were introduced. Whole-expression boxes retain their native frame. The original dependency and its obsolete font bundle are absent from the new app; current software and bundled-font licenses/notices are retained in `THIRD_PARTY_LICENSES`.
- Regression cases exercise the complete synthetic Gaussian formula, bold symbols in fractions, named and starred operators, inline/display rendering, malformed operator/font/color arguments, boxed formulas and the existing glyph/Markdown protections. The synthetic Gaussian glyph render was visually inspected.
- **Motion cause:** the previous version coupled a strongly decelerating shape animation to a separate sleep-driven loading switch. Native frame capture showed a settled circle while the arrow was still present. Disabling the native Send button also dimmed the outgoing arrow immediately.
- **Motion correction:** one interpolated progress value now drives the pill geometry, input fade, arrow fade and loading reveal. The ring blends in before retraction ends; no delayed task switches the stages. The outgoing arrow remains white while becoming noninteractive. The curve has gentler acceleration, and reopening pending/accepted prompts explicitly disables replay animations. Failure reverses from the current presentation; the original filled green success symbol and one-reply rule remain.
- Verification: **149 focused Swift tests passed**, including a 36-frame native capture with multiple distinct intermediate positions and an unchanged composer height; the updated Debug build passed. Native frame sheets and the formula image were inspected. Browser checks cover overlapping arrow/loading feedback, original success glyph, failure/retry, reduced motion and narrow layouts. After relaunching the final Debug app, a synthetic formula response in the already-authorized disposable chat completed and reached the notification path; only sanitized hook counts were checked. This is delivery evidence, while glyph correctness was verified separately in the native render. Native system Reduce Motion, VoiceOver, live pointer timing and multiple-display behavior retain their manual acceptance status.

### Rounded reply-send motion — 2026-11-03

- The user approved the HTML motion and then requested a rounder input and the original success icon. The input now uses a 17-point radius and retracts from the left toward the fixed right-hand arrow in roughly half a second. Its background gathers into a circle, then fades as the loading ring appears. Receipt crossfades to the original SF Symbol `checkmark.circle.fill`, without an extra badge or caption.
- The Uiverse WhiteNervosa `green-donkey-82` reference informed the ring-to-check transition. Its public source and MIT license were inspected; no source or artwork was copied. The original system success symbol is retained. The first reference required login and was not accessed beyond its public login screen.
- Motion is presentation-only: submission starts immediately, one reply remains allowed per response, failed/uncertain sends restore their original draft, and outside inactivity/compact expiry retain their existing behavior. The composer keeps its height during delivery so the response and footer do not shift. A fast acknowledgement waits for the retraction, while reopening an already-pending/received prompt presents its current state without replaying Send. The later continuous-motion refinement replaces the timed task with one interpolated presentation value.
- Reduce Motion replaces spatial retraction with a short fade and the rotating loader with a static dotted ring. The macOS 14 test SDK exposes that environment setting as read-only, so native forced-preference rendering was not automated; the native branch was inspected, and the corresponding browser reduced-motion path was exercised.
- Native system progress rendering was too faint or absent in hosted captures. A small white SwiftUI arc now renders the pending state explicitly; its animation exists only while that indicator is mounted. A pixel-based regression checks that delivery remains visible after the input disappears.
- Validation: the Debug build and 146 focused Swift tests passed, including multiline layout retention, early acknowledgement, failure recovery, native editor behavior and the visible-loader regression. Composing, pending and accepted synthetic native captures were inspected. Browser checks cover the rounded bar, filled success icon, failure/retry, reduced motion and narrow layout. After the final Debug relaunch, a fresh sandbox-to-helper probe reached the already-authorized disposable chat, which completed with the expected synthetic response. The running Debug process recorded two authenticated hook acceptances and zero rejection records; only sanitized counts were inspected. This is transport evidence, not automated typing into the live notch; pointer/focus, native system Reduce Motion, VoiceOver and multiple-display acceptance remain manual cases.

### One accepted reply per response — 2026-11-03

- The user chose one input for each response rather than consecutive submissions from the same preview. Queueing multiple messages only targets a conversation; it does not explicitly bind each message to the particular displayed response.
- The pending multi-message change was removed. Editing is allowed while composing or after a known pre-submission failure; sending, accepted and uncertain states are locked. Accepted replies show the green received mark without a caption. The later approved send motion rolls away the input instead of showing a waiting placeholder. The next authenticated response enables a fresh composer.
- The earlier 450 ms unconditional accepted-send dismissal was removed so the waiting state uses the same outside-inactivity folding and compact-expiry rules for both acknowledgement outcomes. No response-body history or extra submission queue was added to the notch.
- Regression coverage verifies that pending and accepted states reject a second submission, a stale first callback cannot change delivery state, and a new response enables its own reply. Native editing checks verify a read-only received state followed by an editable fresh-response state. Folding and prompt-bound draft expiry retain their existing checks.

### Fold inactive replies and expire their drafts — 2026-11-03

- **Cause:** response keyboard focus blocked automatic closing, while every nonempty draft and send state blocked passive dismissal. That coupled saving a draft to keeping the expanded window and its prompt alive indefinitely.
- **Correction:** response windows now fold after two seconds outside with no keyboard activity. Native editor input and response keyboard navigation renew the deadline; pointer re-entry cancels it. Stale timers are scoped to the same response token. Normal notch surfaces retain their existing close delay and permission decisions retain their existing protections.
- Folding preserves the draft only until the compact prompt expires. After the ordinary three-second unhovered dwell, expiry releases that exact prompt’s draft, delivery feedback and retained response. Reopening or hovering before expiry pauses expiry and restores the draft. Successful explicit opening/dismissal also clears the originating draft instead of carrying it into a future prompt.
- A send already captured for submission can finish after the prompt expires. Its late callback cannot recreate the draft or affect a newer reply. Async send tasks are tracked and cleaned up by request UUID, independently of the lifetime of their originating prompt.
- Validation: 142 focused Swift tests passed, including outside inactivity/re-entry, renewed typing deadlines, matching-prompt expiry, failed/uncertain/accepted-state expiry, and late send callbacks after a new draft was created. Native editor tests confirm editing reports activity to the timer owner. The updated Debug app builds. Live pointer/click-away timing and permission-preemption cases still require observation in that fresh app.
- Manual checks: type while the composer retains keyboard focus, move outside without clicking, and expect a fold after two seconds; hover/reopen before compact expiry and verify the draft; leave again through compact expiry and verify the draft cannot return. Repeat after clicking another app, after Send/green acknowledgement, after failure/uncertain feedback, and while a send is still pending. Continued keyboard input with the pointer outside must postpone folding, and a delayed callback must not revive an expired prompt.

### Quick reply send failure and UI corrections — 2026-11-03

- **Send failure cause:** CLI submission ran inside Boring Notch’s App Sandbox. The earlier native sender tests ran outside that sandbox and therefore missed the packaged-app failure. The user confirmed typing worked but sending produced an error; a signed probe with the product’s actual sandbox entitlements reproduced `unavailable` on the direct path.
- **Correction:** route the reply through the existing `XPCHelperClient` and containing-app-restricted `BoringNotchXPCHelper` service. Resolve the official Codex CLI and validate its exact chat/turn inside that helper. No app entitlements, hook templates, hook configuration, credentials or user settings were broadened or changed. XPC failure preserves the draft as uncertain and never automatically repeats a submission.
- **Boundary regression:** `.github/scripts/test_codex_reply_xpc.py` copies the freshly built production helper into a temporary signed test host with the product’s sandbox entitlements. Against a previously authorized disposable chat, direct submission returned `unavailable`; submission through the real helper returned `queuedNeedsOpen`. The desktop chat then completed with the fixed expected synthetic reply. The temporary host uses the existing product container identity without reading/writing settings; temporary bundles and source files are removed by the harness.
- Reproduce only with an explicitly authorized disposable chat, since this check intentionally submits one fixed synthetic message: `python3 .github/scripts/test_codex_reply_xpc.py --app <fresh-Debug-bundle> --thread <disposable-thread-UUID> --turn <originating-turn-UUID>`.
- **Scrollbar overlap cause/correction:** the macOS overlay indicator shared the response’s right edge with text. The response content now reserves a 16-point trailing gutter. Native long-response rendering is checked with its scroller flashed visible before capture.
- **Requested UI changes:** remove the “Reply to…” caption and the close cross entirely. Keep the matching conversation title in the footer, Escape to collapse, and normal text editing to clear a draft. The user subsequently requested removing the visible Discard draft row as well; it and its unused composer callback are now removed. Positive queue acknowledgements now replace the send arrow with a green check, without a success caption underneath. The mark means Codex received the reply; it does not claim the next task has completed. Four native composer checks passed for this refinement, including the read-only accepted state, and both composing/received renders were inspected before rebuilding and relaunching the Debug app. Failures and uncertain delivery retain their existing error feedback. The empty input remains 34 points high with 11-point text.
- Validation: 137 focused Swift tests and the updated Debug build passed. The sandbox-to-helper regression and real-chat completion passed. Hosted native typing/IME/layout checks pass; live pointer/VoiceOver/multiple-display/permission-preemption coverage retains its pending status below. The sender fix now has evidence at the sandbox/helper boundary, beyond the earlier standalone transport evidence.

### Quick reply implementation evidence — 2026-11-03

- Implementation is on `codex/quick-reply`, branched from response-preview integration `6dd262d`, in `/private/tmp/boring-notch-response-preview`. No push, feature-branch merge, personal-use synchronization or `/Applications` installation is part of this work.
- 137 focused Swift tests passed, including native composer typing, one-line sizing, three-line scrolling, IME confirmation, Return/Shift-Return/Escape, bounded full-card layout, byte-exact argument delivery, failed-send retention, duplicate submission, stale callbacks, safe rejection of shared-session/wrong-turn identities, permission preemption and early server exit. The full native synthetic card was rendered and visually inspected. Eleven embedded-hook tests and the label evaluator passed; the Impeccable detector returned no findings; whitespace checks passed.
- A fresh Debug app was built and launched from `/tmp/boring-notch-codex-refinement/Build/Products/Debug/boringNotch.app`. Only stale Boring Notch instances were stopped. Hooks/templates/configuration were not modified by quick reply. The installed hook points to the canonical Debug bundle, though its source is not byte/AST-identical to the current embedded template; no reconnect or re-trust was performed or claimed.
- With the user's explicit approval, two disposable desktop chats were created. Both the CLI and the actual Swift sender reached the correct existing chat and produced distinct expected final replies in its visible history. For the busy-chat case, a foreground 20-second wait completed normally; the native queued message became a separate subsequent turn. Installed CLI: `0.166.0-alpha.5.1`. It reported accepted queue writes and a resume warning because no local daemon was available, while the already-loaded desktop chats consumed those messages successfully.
- After launching the fresh Debug app, two native test sends produced four authenticated hook acceptances in that process and zero rejection records. Only sanitized counts were inspected; no private response text, tokens or permission payloads were logged into this guide.
- Root causes corrected during implementation: Foundation Process normalized composed Unicode in argv, so the sender now uses explicit UTF-8 `posix_spawn` arguments, verified byte for byte; delayed accepted-send cleanup could match a newer send, so cleanup is guarded by request identity and the captured presentation token; a retained response could survive Dismiss, so explicit dismissal releases only its matching retained notice. Early server exit also suppresses SIGPIPE and keeps the failure inside the send operation.
- **Live checks still pending:** typing/sending through the actual notch panel, real pointer/focus return, VoiceOver, multi-display/small-screen behavior, live permission preemption and the entire card-dismissal/new-preview sequence. macOS accessibility automation was unavailable in this session. Native hosted-view tests and actual transport/hook delivery are evidence for their own boundaries, not substitutes for these remaining checks. A forked/shared-session chat is intentionally unavailable unless exact identity can be proved.

| Case | Action | Expected |
| --- | --- | --- |
| Short reply | Ask for one short sentence, then hover or activate the notice | Card fits the content without a large blank viewport |
| Formatting | Ask for headings, emphasis, a Markdown table, a nested list, a web link, Unicode, and fenced Swift | Actual table columns, readable code, and preserved line breaks; links open only when activated |
| Math | Ask for Greek letters, subscripts and a fraction using `\(...\)` and `\[...\]`, plus dollar delimiters and a literal code example | Inline and display math typeset locally; code and currency stay literal; the card still fits or scrolls |
| Chat title | Use a long named conversation and hover its response | Matching title appears at bottom left, with Open in Codex kept visible |
| Long reply | Ask for a long formatted explanation | Card stops growing; body scrolls; Open in Codex remains visible |
| Beyond the cap | Ask for a reply longer than 16,000 code points | Prefix retained and `...` visible at the end, including when the cutoff is inside a fence/table |
| Missing text | If a real Stop without text is reproducible | Codex update; no invented preview |
| Pointer boundary | Move from compact notice into the card, scroll, then leave | Card stays open while hovered; after two idle seconds outside it folds and restarts the three-second dwell |
| Keyboard / VoiceOver | Activate the compact notice; navigate response, scrollbar, link and button; press Escape | Preview and matching chat are reachable; keyboard activity renews the outside inactivity timer; Escape collapses |
| Open failure / retry | Make the official Codex app unavailable in a controlled setup, activate Open, then restore and retry | Error remains in the card for retry; only successful opening dismisses the matching notice; leaving still restores passive dismissal |
| Replacement | Start a new turn or let another chat/permission become visible during reading or opening | Old preview clears; old callbacks cannot dismiss or open the replacement chat |
| Two displays | Expand on one display, then interact on another | Hover and collapse ownership stay with the right display; no unsolicited expansion on every display |
| Geometry | Check a small display, camera clearance, normal notch and permission card | Content and action remain reachable; normal/permission dimensions retain their existing sizes |

Repeat the Allow, Deny, Review in Codex, automatic-review and concurrent-chat cases below. Synthetic URL delivery and native rendering measurements do not substitute for these real cases.

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

### Response preview implementation — 2026-11-03

- Worktree: `/private/tmp/boring-notch-response-preview`, branch `codex/response-preview`, based on `4bff8b5`.
- Debug bundle: `/tmp/boring-notch-codex-refinement/Build/Products/Debug/boringNotch.app`.
- Automated validation: 114 Swift tests, including response retention/correlation, display ownership, native Markdown sizing, table structure, incomplete syntax, link schemes and disabled images. All 11 embedded-hook tests passed, covering the actual Python → signed URL → Swift path, exact and exceeded caps, combining/multibyte text, JSON escaping, response delivery budgets and unchanged large-permission delivery. The label evaluator, Debug build and `git diff --check` passed.
- A synthetic short response and an exactly-at-cap 16,000-emoji response both reached the Debug process through native authenticated URL delivery. This was a transport smoke check before the last permission-budget correction, not a real-conversation or final live acceptance result.
- The user confirmed updating and trusting the initial response-preview hook. The last review then restricted the new URL budget to Stop events so permission transport remains unchanged. **Connect or update Codex and review/trust that final hook again before later live tests.** No trust fingerprints were edited automatically.
- The personal `/Applications/boringNotch.app` process remained running; an initial normal stop request did not terminate it. Only the stale Debug process was subsequently force-stopped for its rebuild. The installed app was not replaced.
- **Live acceptance pending:** the user elected to test later. Short/long real replies, formatted tables/code, pointer transitions, successful/failed opening and retry, new-turn/replacement behavior, concurrent chats/displays, VoiceOver, and the permission matrix are not recorded as passed. Installed Codex version is not independently recorded for these cases yet.
- Review corrections: replay suppression now retains a digest instead of a message-bearing payload; detail ownership is scoped to the exact notification and display so stale collapse callbacks cannot close another card; response URL sizing does not alter permission event delivery. Regression coverage accompanies these changes.
- At this checkpoint the feature was held for final live checks. The later user-requested local integration is recorded below; unchecked cases remain open.

### Response preview layout regression — 2026-11-03

- User screenshots demonstrated two failures: the expanded card could clip into its header, or leave a large blank area while showing only one reply line. These reports supersede any inference that renderer-only sizing tests established working card layout.
- Reproduction used the actual response view with synthetic text inside a 640 × 270 native hosting window, a 34-point camera inset, the app's horizontal padding, and the same parent-height feedback. Repeated rendering passes left the preference callbacks at their defaults: card height **0**, reply viewport **20**. Adding the camera/bottom clearance to the zero value collapsed the parent to **46** points. Retaining the maximum parent height instead reproduced the large blank card with one visible line.
- Cause: background preference-based measurements were not delivering the rendered dimensions through this constrained hierarchy. Both the viewport and its parent relied on those values. The previous native tests measured only standalone Markdown fitting size and missed this feedback path.
- Correction: replace the two preference measurements with direct `onGeometryChange` observations; discard nonpositive card dimensions and anchor the reply at the top. The complete card is now in `CodexResponseRendering`, while app notification routing and keyboard/window coordination remain in the app wrapper. Obsolete preference keys were removed.
- Verification: the complete production card now settles at **132** points for the synthetic short reply and **250** points for the long reply. The long body's native viewport is **138** points with a **1,445**-point document; tests verify actual scrolling, a top initial position, and space outside the scroller for the header/action. The full suite passed **116 Swift tests** and the fresh Debug build passed. These are native synthetic regression results, not completion of the real-conversation matrix.
- The rebuilt Debug copy was launched; the personal app was left running. This correction changes no hook code. The installed hook still differs from the final repository template from the earlier transport correction, so the outstanding connect/update/trust step still applies before final hook acceptance.

### LaTeX and chat-title refinement — 2026-11-03

- The user confirmed normal expansion, then reported literal LaTeX in the response body and requested the conversation title in the footer. This confirms the basic expansion correction; it does not complete the remaining acceptance matrix.
- Cause: GFM does not include LaTeX typesetting, and CommonMark escape processing consumes the backslashes on `\(` / `\[` delimiters before rendering.
- Correction: preserve paired parenthesis/bracket and dollar math before Markdown parsing, protect code/link/image/HTML regions using the existing cmark AST, and typeset expressions using the official pinned iosMath 2.5.0 library. Math becomes locally generated glyph images with stable digest identifiers, never remote image URLs or executable TeX. Unsupported expressions remain readable; bitmap allocation is bounded. External images remain omitted and cannot cancel sibling inline math rendering.
- The footer now uses the notification's `chatTitle`; long titles stay on one line with a full-title tooltip while Open in Codex keeps its width.
- Synthetic native verification includes actual nontransparent glyph pixels for Greek letters, conditional probability subscripts, fractions and matrices; code/currency protection; unsupported math; stable private identifiers; and the existing complete-card sizing/scrolling tests. The mixed native fixture was visually checked with inline theta, a display probability/fraction expression and the conversation-title footer. Runtime dependency and bundled font notices are retained in `THIRD_PARTY_LICENSES`. All 122 Swift tests, the fresh Debug build and `git diff --check` passed; the Debug copy was relaunched without stopping the personal app. Real conversation math and title checks remain pending.

### Approved response styling — 2026-11-03

- The user approved the native **Seamless** preview: 11-point body text, softer white lettering and no gray reply panel. Inline math uses 11 points and display math 13, matching the preview. Header, footer, chat title, actions and height/scroll behavior retain their existing styling and layout.
- Cause of the previous mismatch: the Markdown theme's own text style restored 16-point text and a gray background after the surrounding text environment was set. The approved implementation overrides the theme's text style directly and removes the ineffective environment override.
- Verification: all **123 Swift tests** passed, including a native test comparing the effective font with 11-point system text and checking that empty reply pixels are transparent so the black notch shows through. The fresh Debug build and whitespace checks passed. This styling change does not modify hooks. Remaining real-conversation acceptance is still tracked above.

### User-requested local integration — 2026-11-03

- After confirming normal expansion and approving the Seamless styling, the user explicitly requested merging the current implementation into `feature/codex-notification`.
- Both worktrees were inspected. The destination was clean and both branches started at `4bff8b5`, allowing a fast-forward integration without overwriting unrelated work.
- Validation available for this integration: 123 Swift tests, 11 embedded-hook/delivery tests, the notification-label evaluator, a fresh Debug build, native synthetic rendering checks and whitespace checks passed.
- The merge is authorized with the remaining live acceptance cases still open. In particular, do not interpret this integration as confirmation of final-hook trust, the full permission matrix, concurrent chats/displays, VoiceOver or every opening/retry case. Those checks retain their recorded pending status.
- Scope is local integration only. No remote push, personal-use synchronization, installed-app replacement or runtime restart is requested as part of this merge.

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
