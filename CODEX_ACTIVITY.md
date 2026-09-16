# Local Codex activity

The optional Codex activity avatar follows the validated count of unfinished top-level tasks in Codex Desktop, including tasks waiting for input or approval. Subagents, hidden side conversations, temporary conversations, archived tasks and internal pull-request-fix automations are excluded. It automatically selects an avatar by task count. Completed, unavailable, stale, invalid and error states return to the existing Smile. An amber dot marks input or approval requests; a red dot marks an error. macOS Reduce Motion keeps the task glyphs still.

| Tasks in progress | Automatic avatar | Rotation speed |
| --- | --- | --- |
| 0 or unavailable | Existing Smile | Existing behavior |
| 1–2 | Lines | 1× |
| 3 | Orbit | 1× |
| 4 or more | Colorful orbit | 1.15× at 4, increasing toward 2.5× |

For four or more tasks, the speed multiplier is `1.15 + 1.35 × (count − 4) / (count − 4 + 6)`. Speed changes preserve the current rotation angle. Waiting tasks count toward the same tiers as running tasks.

The automatic avatar appears in the idle slot and beside paused music when live monitoring is enabled. The manual picker remains available when monitoring is off and during the three-second Preview. Playing music and notification presentation keep their existing behavior. Smile remains the manual default, and local activity monitoring is disabled initially.

## Setup

The native app is sandboxed. A separate, optional Python bridge reads the local Desktop IPC socket and serves aggregate state over loopback. Python 3 and tmux must be available on the Mac.

From the source checkout, run:

```sh
./script/start-codex-activity-bridge.sh
```

The bridge runs in the named tmux session `boringnotch-codex-activity`. The startup script reuses an existing session with that name. To observe its output:

```sh
tmux attach -t boringnotch-codex-activity
```

In **Settings → Appearance → Idle avatar**, enable the avatar and **Follow local Codex activity**. The follow toggle is available even when the manual choice is Smile. Live monitoring overrides the manual picker; Preview temporarily shows the manual choice at its normal speed for three seconds without starting a Codex task.

Optional login startup is installed separately:

```sh
./script/install-codex-activity-login.sh
```

The installer copies the bridge into `~/Library/Application Support/boringNotch/CodexActivity` and creates `~/Library/LaunchAgents/theboringteam.boringnotch.codex-activity-login.plist`. The login agent starts the same tmux session; it does not host the server itself. Logs are stored in `~/Library/Logs/boringNotch/codex-activity.log`.

To stop the running bridge, send Control-C in its tmux session. Disabling **Follow local Codex activity** stops the app's requests but leaves this separately managed bridge running. To remove login startup:

```sh
launchctl bootout "gui/$(id -u)/theboringteam.boringnotch.codex-activity-login"
rm "$HOME/Library/LaunchAgents/theboringteam.boringnotch.codex-activity-login.plist"
```

## Data flow and compatibility

The bridge uses Codex Desktop's private local IPC protocol, not a supported public API. It identifies the app-server process owned by Desktop and discovers candidate task IDs from local session filenames and modification times. It does not open session transcript files. Incoming IPC frames are validated and projected in bounded chunks; only runtime status, task classification, revision, owner and freshness metadata are retained. Prompts, titles, responses and tool output are discarded and never logged or returned through HTTP.

Task classification uses Desktop's explicit `source`, `threadSource`, `parentThreadId`, `ephemeral` and `sideConversation` metadata from the same status stream. It does not infer task type from titles or read a database. Ordinary forked tasks remain eligible; a fork origin is not a subagent parent. Unknown classification metadata is excluded until a valid snapshot arrives. Classification changes require a fresh snapshot, and archive/unarchive events remove or restore eligibility. These rules distinguish top-level tasks from their workers on the supported Desktop protocol; they do not reproduce every UI-specific sidebar filter across future versions.

`http://127.0.0.1:48731/activity` exposes only the service name, schema version, aggregate phase, active task count and a timestamp. The endpoint binds to loopback, rejects browser-origin requests and accepts only the expected Host header. The native client does not follow redirects. No credentials are required or stored.

Stream version 11 snapshots and revision-checked patches are supported. The bridge requests fresh snapshots after gaps or owner changes, refreshes quiet subscriptions, and clears activity when Desktop exits or the IPC connection fails. Unknown protocol versions and expired observations remain still. Future Desktop protocol changes may require a bridge update. Standalone CLI sessions and remote hosts are outside this integration's scope.

## Resource use

The frame reader consumes at most 64 KiB per socket read and validates UTF-8 and JSON as it advances. Complete ignored values within a chunk can be decoded temporarily by CPython's C decoder and then discarded. Larger strings and containers are consumed incrementally. Limits on retained scalar lengths, paths and arrays bound the activity projection. The 64 KiB input limit is not a limit on total process memory: Python and temporary decoded objects also consume memory. Desktop still sends full conversation snapshots through this private protocol, so chunked parsing does not eliminate their transmission or serialization cost.

The bridge caches the verified Desktop/server process identity and session file paths. Original and segmented rollout filenames resolve to the same task ID; an appended segment ID is not treated as another task. A two-second maintenance cycle checks process lifecycle notifications and cached file modification times, including files in older session directories. On macOS, directory notifications trigger structural rescans; a periodic reconciliation also refreshes the cache. When notification coverage is unavailable, discovery falls back to polling. Session file contents are never read.

Verified top-level subscriptions remain attached through idle, error and not-loaded states so resumed activity arrives through runtime patches even when no rollout file is written. Confirmed hidden tasks release their subscriptions instead of refreshing their activity. Quiet active subscriptions, including tasks waiting for input or approval, request a fresh snapshot after 30 seconds; active observations expire after 45 seconds without confirmation. Idle subscriptions do not request periodic snapshots. File changes, owner announcements and reconnects still discover or revalidate tasks. An unanswered probe releases its subscription after eight seconds and retries after a 30-second backoff, so unknown tasks do not remain permanent followers.

Keeping verified followers can prevent Codex Desktop from releasing inactive conversation history. This preserves timely activity updates but can increase memory retained by Desktop itself; bounded bridge parsing does not bound Desktop's memory. Stopping the bridge disconnects its followers and restores Desktop's normal cleanup eligibility.

The native app continues to request the aggregate endpoint once per second. Discovery intervals are scheduling cadences, not an end-to-end latency guarantee: rollout writes, IPC delivery and task duration can affect when a resumed task is observed.

Representative synthetic measurements compare the previous full-frame decoder with the bounded reader. Each case used an identical generated fixture, a fresh Python 3.14.4 worker, warm file reads and one measured run; imports and fixture generation were excluded.

| Synthetic frame | CPU seconds: full frame → bounded reader | Peak RSS MiB: full frame → bounded reader |
| --- | ---: | ---: |
| 32 MiB, one large ignored string | 0.034 → 0.116 | 123.92 → 27.50 |
| 32 MiB, many small turn objects | 0.091 → 0.221 | 217.84 → 27.59 |
| 128 MiB, one large ignored string | 0.143 → 0.464 | 411.98 → 27.61 |
| 128 MiB, many small turn objects | 0.361 → 0.888 | 796.80 → 27.62 |

All cases produced the same activity projection. These runs show the memory/CPU tradeoff of parsing alone; they exclude the process-discovery cache and subscription changes. They are not universal memory ceilings or live-service speedup estimates.

## Artwork provenance

Orbit, Lines and Colorful orbit are original SwiftUI drawings made from circular arcs, a center dot and rounded parallel bars. Their geometry, colors and continuous rotation are defined in `boringNotch/components/Notch/CodexAvatarView.swift` under this repository's GPL-3.0-only license. No OpenAI logo, recovered SVG, raster image, Lottie file, traced path or copied animation curve is included. The existing Smile artwork is unchanged.

All original glyphs retain full opacity across state and speed changes. Reduce Motion pauses rotation at its current angle. Manual glyphs remain still when monitoring is off; automatic mode returns to Smile when no validated task is in progress.

## Validation

```sh
./script/check-codex-activity.sh
```

The checks use synthetic IPC messages and task IDs, validate phase/freshness handling and published counts, exercise chunk boundaries and malformed frames, cover discovery and subscription lifecycles, exercise tier boundaries and rotation continuity, typecheck the native client, and render counts 0, 1, 2, 3, 4, 8 and a large count offscreen alongside resting, rotated and Reduce Motion states. They neither connect to Codex nor start the bridge. The app uses the standard `boringNotch` Xcode scheme.
