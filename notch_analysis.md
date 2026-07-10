# boring.notch — CPU / Compute Efficiency Analysis

**Scope:** Backend / logic layer only. This document began as an analysis and remediation
plan; the first implementation pass is now recorded below. Frontend visual design and
layout remain intentionally untouched. Where a SwiftUI view is named, it is because the
view drives continuous compute such as a timer, `TimelineView`, or infinite animation.

**Goal:** Reduce the app's steady‑state CPU usage. The user's complaint is *continuous*
CPU percentage, so findings are ranked primarily by **how much work happens while the
user is doing nothing** (idle, or music simply playing with the notch closed), and only
secondarily by per‑interaction cost.

**Method:** Every claim below was verified by reading the actual source (file:line cited).
A number of "obvious" suspects turned out to be non‑issues on the default code path; those
are listed explicitly in [§7 Myth‑busting](#7-things-that-look-expensive-but-arent) so
time isn't wasted chasing them.

> **Cross‑analysis note (revision 2):** This document was reconciled against a second,
> independent static analysis (`codex_notch_analysis.md`). Where that analysis surfaced
> valid findings I had not covered, I re‑verified each against source and folded them in —
> they are marked **[cross‑checked]**. The two analyses agree on the big media findings
> (un‑debounced stream, fragmented `@Published` publishes, per‑pixel `averageColor`, stale
> per‑line allocations). The other analysis is notably stronger on **startup/lifecycle**
> (eager singleton construction) and **subsystem breadth** (Shelf/Quick Share, HUD media‑key
> path, image processing); this version is more precise about **which media path is actually
> the default** and about separating real idle costs from interaction‑only costs.

---

## Implementation status — 2026-07-10

The following roadmap items have been implemented and compile successfully:

| Original finding | Status | Implemented change |
|---|---|---|
| §3.1 MediaRemote stream | ✅ Done | Added `--debounce=200` to the adapter process and reused the stream's `ISO8601DateFormatter` and `JSONDecoder`. |
| §3.2 Closed-notch visualizers | ✅ Done | Spectrum and Lottie playback now stop while occluded, while the app is hidden, and in Low Power Mode. Spectrum ticks were reduced from 3.3 to 2.5 per second with timer tolerance. |
| §3.3 Animated face timer | ✅ Done | Replaced the leaked repeating timer with a SwiftUI lifecycle-cancelled task. |
| §3.4 Eager subsystem startup | 🟡 Partial | Removed Quick Share discovery from startup, removed the AppDelegate's eager Quick Share reference, made the media-controller default side-effect free, and gated fullscreen monitoring. Battery, volume, brightness, webcam, and the main media service still need explicit lifecycle APIs. |
| §4.1 Artwork average color | ✅ Done | Replaced the full bitmap/per-pixel loop with `CIAreaAverage` to a 1×1 output and reused a shared `CIContext`. |
| §4.2 Fragmented media publications | 🟡 Partial | Avoided redundant `timestampDate` publication. A larger snapshot-based `MusicManager` refactor remains. |
| §4.3 Stream allocations | ✅ Done | Cached the date formatter and JSON decoder. The pipe handler's readability mechanism was not redesigned. |
| §4.4 Open refresh and artwork comparisons | ✅ Done | Added a three-second stale gate for open-time refreshes and replaced full artwork `Data` comparisons with a constant-cost sampled signature. |
| §5.4 Fullscreen detector | ✅ Done | Monitoring now stops when hiding is `.never`; duplicate fullscreen dictionaries are not republished. |
| §6.6 Quick Share startup | ✅ Done | Provider discovery is lazy, idempotent, and protected from concurrent duplicate discovery. |
| §7 Apple Music / Spotify scripts | ✅ Done | Distributed playback notification bursts are debounced by 200 ms before AppleScript refreshes. |

Additional implementation details:

- `Defaults.Keys.mediaController` now defaults statically to `.nowPlaying`; the asynchronous compatibility check in `MusicManager` retains the Apple Music fallback where MediaRemote is unavailable.
- Lottie animation state is managed by an `NSView` host that responds to window/application occlusion and power-mode notifications.
- Artwork identity uses the data length plus 32 evenly distributed sampled bytes. This is intended for UI change detection, not cryptographic integrity.
- Quick Share still discovers providers when the shelf sharing UI or its settings page is first opened, so behavior is deferred rather than removed.

Verification:

- A Debug macOS build succeeds with code signing disabled.
- `git diff --check` reports no whitespace errors.
- The only final linker warning is the pre-existing deployment-target mismatch: `MediaRemoteAdapter.framework` targets macOS 15 while the app targets macOS 14.
- No before/after CPU percentage is claimed yet because Instruments and `powermetrics` measurements have not been run.

Remaining priority work:

1. Publish media metadata/timeline snapshots rather than many independent `@Published` fields.
2. Add start/stop lifecycle control for battery, CoreAudio volume, brightness, webcam, and the main media service.
3. Replace per-screen expanded-drag global monitors with one shared monitor.
4. Coalesce CoreAudio and brightness XPC operations during key repeats.
5. Debounce shelf persistence, calendar reloads, and window rebuild notifications.
6. Bundle the default Lottie animation locally.
7. Run the measurement plan in §9 and record before/after CPU and wake-up results.

The sections below are intentionally retained as the **pre-change baseline and rationale**.
Code excerpts showing zero debounce, full-image scanning, leaked timers, unconditional
fullscreen monitoring, or eager Quick Share discovery describe the state before this
implementation pass and should be read with the status table above.

---

## 1. How the media path actually works (important context)

This reframes most of the media findings, so read it first.

- The **default** media controller is `NowPlayingController`
  (`MusicManager.swift:121‑124`, selected unless the user changes the *Media Controller*
  preference). It does **not** use AppleScript polling.
- `NowPlayingController` launches a **long‑lived `/usr/bin/perl` subprocess** running
  `mediaremote-adapter.pl … stream` (`NowPlayingController.swift:200‑201`, `210`) for the
  **entire lifetime of the app**. That process observes Apple's private MediaRemote
  framework and emits **JSON lines** on stdout.
- Those lines are read by an `actor JSONLinesPipeHandler`, decoded
  (`NowPlayingController.swift:394‑404`), turned into a `PlaybackState`
  (`handleAdapterUpdate`, `:229‑300`), published, and applied on the main thread by
  `MusicManager.updateFromPlaybackState` (`MusicManager.swift:182‑292`).
- The `AppleMusicController` / `SpotifyController` / `YouTubeMusicController` are the
  AppleScript / HTTP‑polling controllers. They run if the user explicitly selects them —
  **and** `AppleMusicController` becomes the *automatic fallback default* on macOS versions
  where MediaRemote is deprecated (`isNowPlayingDeprecated == true`, see §3.1). So "AppleScript
  is not the default" holds **only** while MediaRemote still works; on locked‑down macOS the
  AppleScript path *is* the default and its per‑notification cost (§7) becomes a primary
  concern.

Consequence: the media subsystem's steady‑state cost is dominated by **(a)** the perl
process baseline, **(b)** how chatty the stream is (and whether it's coalesced), and
**(c)** the always‑on visualizer animation in the closed notch — not by AppleScript.

---

## 2. Severity / effort legend

| Tag | Meaning |
|-----|---------|
| 🔴 **Continuous** | Burns CPU while the user is idle or just listening to music. Highest priority. |
| 🟠 **Per‑change** | Cost is paid on every state update; scales with how chatty the source is. |
| 🟡 **Event** | Only on infrequent events (battery %, calendar edit, volume key). Low CPU, but wasteful. |
| 🔵 **Interactive** | Only while the notch is open / being hovered. Not an idle cost. |
| ⚪ **Burst** | Pathological only during display reconfiguration / settings changes. |

Effort: **S** = localized change, **M** = moderate refactor, **L** = larger redesign.

---

## 3. Tier 1 — Continuous / always‑on (fix these first)

### 3.1 🔴 Un‑debounced MediaRemote stream + permanent perl process — **S/M**

**Where:** `NowPlayingController.swift:200‑201` (launch), `:220‑226` & `:394‑404` (decode),
`:229‑300` (apply); the script's own docs at `mediaremote-adapter.pl:55‑57`.

**What & how often:** The stream is started with:

```swift
process.arguments = [scriptURL.path, frameworkPath, "stream"]   // :201  — NO --debounce
```

The adapter script documents a throttling lever that is **not being used**:

```
stream
  --no-diff: Disable diffing and always dump all metadata
  --debounce=N: Delay in milliseconds to prevent spam (0 by default)   ← default 0
```

With `--debounce=0`, **every** MediaRemote notification is emitted immediately. Some media
apps are "spammy" (the option exists precisely because of that). Each emitted line walks
the full pipeline: actor wake‑up → `JSONDecoder().decode` → `handleAdapterUpdate` builds a
new `PlaybackState` → `@Published playbackState` fires → `updateFromPlaybackState` runs on
the **main thread** → potentially several `@Published` writes → SwiftUI invalidation.

**Why it's costly:**
- A **perl interpreter runs for the app's whole lifetime**, even with no music. That's a
  fixed baseline cost (process + framework observers) the app pays unconditionally.
- Zero coalescing means bursts of notifications (track change, seeking, an app launching,
  a chatty player updating elapsed time) each trigger a full main‑thread update cycle.
- **[cross‑checked] A *second* perl process is spawned at startup.**
  `MediaChecker.checkDeprecationStatus()` (`helpers/MediaChecker.swift:18‑66`, kicked off
  from `MusicManager.init`, `:81‑92`) launches `/usr/bin/perl … test` plus a test client and
  **waits up to 10 s** for it to exit. One‑time, not continuous — but it is launch‑time CPU
  the app pays before the user does anything, and its result (`isNowPlayingDeprecated`)
  decides the default controller (see note below).

> **Important nuance about the "default" path.** `Defaults.Keys.defaultMediaController`
> (`models/Constants.swift:193‑199`) returns `.appleMusic` when
> `MusicManager.shared.isNowPlayingDeprecated` is true. On macOS versions where Apple has
> locked down MediaRemote, the **AppleScript** `AppleMusicController` becomes the *default*
> controller — so the AppleScript‑per‑notification cost (see §7) is the real default path
> for those users, not an opt‑in edge case. Two consequences: (1) resolving this default
> **constructs `MusicManager.shared`** just to read a flag, eagerly booting the media
> subsystem (see §3.4); (2) the AppleScript controllers deserve the coalescing fixes in §7
> on exactly the systems where MediaRemote no longer works.

**Fix:**
1. **Pass `--debounce`** (e.g. `120`–`250` ms): change `:201` to
   `["…", frameworkPath, "stream", "--debounce=200"]`. This is the single highest‑leverage,
   lowest‑risk change in this document — the adapter coalesces upstream, before any Swift
   code runs. (S)
2. The smoothly‑moving progress bar does **not** need frequent stream updates — the UI
   already extrapolates position from `timestampDate + elapsedTime * playbackRate`
   (`MusicManager.estimatedPlaybackPosition`, `:567‑573`). So debouncing the stream costs
   nothing visually.
3. Cache the per‑line allocations (see §4.3). (S)

---

### 3.2 🔴 Always‑on music visualizer in the closed notch — **M**

**Where:** `ContentView.swift:451‑468` (the closed‑notch live‑activity HStack),
`MusicVisualizer.swift:57‑87` (`AudioSpectrum`), `LottieAnimationView.swift:11‑20`
(`LottieAnimationContainer`).

The closed, always‑visible notch shows one of two visualizers whenever music is playing
and the music live activity is enabled (`ContentView.swift:290`):

```swift
if useMusicVisualizer {
    … AudioSpectrumView(isPlaying: $musicManager.isPlaying) …   // :462
} else {
    LottieAnimationContainer()                                   // :466
}
```

**Path A — `AudioSpectrumView` (a `Timer`‑driven `NSView`):**

```swift
animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { … updateBars() }  // :59
…
private func updateBars() {                       // :70‑87
    for (i, barLayer) in barLayers.enumerated() { // 4 bars
        let targetScale = CGFloat.random(in: 0.35 ... 1.0)   // not real audio — random
        let animation = CABasicAnimation(keyPath: "transform.scale.y")  // new object each tick
        …
        barLayer.add(animation, forKey: "scaleY")
    }
}
```
- Fires **3.3×/second** for the entire duration of playback, creating ~13 `CABasicAnimation`
  objects/second and keeping Core Animation busy.
- The bars are driven by `CGFloat.random` — it is **not** an audio spectrum, just motion.
  So the visual value is decorative, but the cost is real and continuous.
- It is correctly stopped when playback pauses (`setPlaying(false)` → `stopAnimating`,
  `:97‑104`), **but it is not paused when the notch's window is occluded/off‑screen**, nor
  throttled in Low Power Mode.

**Path B — `LottieAnimationContainer` (an infinite Lottie loop):**

```swift
LottieView(url: URL(string: "https://assets9.lottiefiles.com/…/lf20_mniampqn.json")!,
           speed: 1.0, loopMode: .loop)            // :15  — default visualizer
```
- An **infinitely looping** (`loopMode: .loop`) vector animation. Lottie rasterizes vector
  paths per frame; unless the Core Animation rendering engine is explicitly selected this
  runs on the **main thread at display refresh** — a meaningful continuous cost in an
  always‑visible window during playback.
- The **default** asset is fetched from a **remote URL** every time the view appears
  (network + decode), instead of being bundled.

**Why it's costly:** Whichever branch is active, *something animates continuously the whole
time music plays*, in the always‑on closed notch. This is very likely the **largest
playback‑time CPU contributor** after the perl process.

**Fix:**
- **Gate on actual visibility.** Pause both visualizers when the notch window is occluded
  / on another Space / the display is asleep (`NSWindow.occlusionState`,
  `NSApplication.didChangeOcclusionState`), and when `ProcessInfo.isLowPowerModeEnabled`.
- For Lottie: select the **Core Animation rendering engine** (offloads interpolation to
  the render server) and **bundle the default animation locally** instead of fetching from
  lottiefiles.com.
- For `AudioSpectrum`: a 0.3 s tick is already modest; the bigger win is pausing it when
  not visible. Optionally drop to ~0.4–0.5 s.

---

### 3.3 🔴 `AnimatedFace` blink timer is leaked and never stops — **S**

**Where:** `AnimatedFace.swift:43‑59`.

```swift
.onAppear { startBlinking() }              // :43‑45  — no .onDisappear
func startBlinking() {
    Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in …  }   // :49 — not stored
}
```

**What & how often:** Started in `onAppear`, the timer is **never assigned to a property and
never invalidated**. It is retained by the run loop and keeps firing **every 3 s forever**,
even after the face view disappears. Because `startBlinking()` runs on every `onAppear`,
**each re‑appearance stacks another permanent timer**.

**Why it's costly:** A periodic 3 s wake‑up (× however many times the idle face has ever
appeared) that schedules SwiftUI spring animations — pure waste once the face is no longer
shown. The face itself is only meant to appear when the player is idle and
`showNotHumanFace` is on (`ContentView.swift:293`).

**Fix:** Store the timer in `@State`, guard against double‑start, and invalidate it in
`.onDisappear`. Standard timer‑lifecycle hygiene.

---

### 3.4 🔴 [cross‑checked] Every subsystem boots eagerly at view construction — **M/L**

**Where:** `ContentView.swift:19‑25`; `models/BoringViewModel.swift:14, 40`;
`boringNotchApp.swift:59`; `models/Constants.swift:193‑199`.

This is the *why* behind a lot of idle CPU: building the notch UI eagerly constructs and
**starts** every backend subsystem, whether or not its feature is enabled or visible.

```swift
// ContentView.swift:19‑25 — every one of these is a side‑effectful singleton
@ObservedObject var webcamManager     = WebcamManager.shared          // checks camera availability in init
@ObservedObject var musicManager      = MusicManager.shared           // spawns perl deprecation check + stream controller
@ObservedObject var batteryModel      = BatteryStatusViewModel.shared // starts IOKit power monitoring
@ObservedObject var brightnessManager = BrightnessManager.shared
@ObservedObject var volumeManager     = VolumeManager.shared          // registers CoreAudio listeners + reads volume
// BoringViewModel.swift:14,40
@ObservedObject var detector = FullscreenMediaDetector.shared          // starts a MacroVisionKit space stream in init
let webcamManager = WebcamManager.shared
// boringNotchApp.swift:59
var quickShareService = QuickShareService.shared                       // init() runs share‑provider discovery
```

**Why it's costly:**
- The app *looks* like a tiny notch, but the moment its window exists it has started: the
  media stream (perl), CoreAudio listeners, an IOKit power source, a MacroVisionKit space
  stream, camera‑availability enumeration, and share‑provider discovery — **regardless of
  which features the user actually enabled**. That's the baseline idle cost.
- Work happens in `init`, not behind a `start()`. Constructors should allocate fields, not
  launch processes/listeners.
- `Defaults.Keys.defaultMediaController` reading `MusicManager.shared` (`Constants.swift:194`)
  means even *resolving a default setting* boots the whole media subsystem.

**Fix (backend‑only, no visible behavior change):**
- Make these initializers side‑effect‑free; add idempotent `start()/stop()` (or
  `startIfNeeded`) methods.
- Start each subsystem from `AppDelegate` (or a small `FeatureRuntimeCoordinator`) based on
  the relevant `Defaults` flag and current visibility — e.g. don't start the fullscreen
  detector when `hideNotchOption == .never` (§5.4); don't run Quick Share discovery until the
  shelf is first used; don't start the camera path until the mirror is shown.
- Break the `Defaults → MusicManager.shared` coupling: default to `.nowPlaying` statically,
  then migrate/fallback after the async deprecation check completes.
- Existing `.shared` references in the views keep working — only the *side effects* move out
  of construction. This is the single biggest structural lever for **idle** CPU.

---

## 4. Tier 2 — Per‑change inefficiency (scales with update frequency)

### 4.1 🟠 `averageColor` decodes the full image and sums every pixel on the CPU — **S**

**Where:** `extensions/NSImage+Extensions.swift:19‑106`; invoked from
`MusicManager.calculateAverageColor()` (`:575‑583`) → `updateAlbumArt` (`:556‑564`), gated
by `Defaults[.coloredSpectrogram]`, on **every artwork change**.

```swift
context.draw(cgImage, …)                       // :45  full‑resolution redraw into RGBA
for i in 0..<totalPixels {                      // :60‑65  O(width × height) on the CPU
    totalRed   += UInt64( color        & 0xFF)
    totalGreen += UInt64((color >>  8) & 0xFF)
    totalBlue  += UInt64((color >> 16) & 0xFF)
}
```

**Why it's costly:** Album art is commonly 600×600–3000×3000. This allocates a full‑size
RGBA bitmap and iterates **every pixel** (360k–9M iterations) on the CPU, on a background
queue but still burning a core, on each track change. It re‑runs even if the same artwork
reappears.

**The fix already exists in the same file.** `getBrightness()` (`:108‑136`) uses the
GPU‑accelerated `CIFilter.areaAverage` and renders to a **1×1** bitmap. Average color
should do the same, or — even cheaper — draw the `cgImage` into a **1×1 (or 8×8)
`CGContext`** and read back the single averaged pixel (CoreGraphics does the downsample via
interpolation). Either reduces the work from O(pixels) to ~O(1).

Additionally: **cache** the computed color keyed by an artwork hash (the manager already
tracks `artworkData` and `lastArtwork*`), so re‑shown tracks skip the computation entirely.

---

### 4.2 🟠 `updateFromPlaybackState` fans one update into many SwiftUI invalidations — **M**

**Where:** `MusicManager.swift:182‑292`.

The method correctly diffs each field, but then writes them as **separate `@Published`
properties** (`songTitle`, `artistName`, `album`, `elapsedTime`, `songDuration`,
`playbackRate`, `isShuffled`, `bundleIdentifier`, `repeatMode`, `isFavoriteTrack`,
`volume`, `timestampDate` — `:246‑291`), several inside `withAnimation(.smooth)` (`:187`).
`MusicManager` has **24 `@Published` properties** (`:32‑55`) and is observed across the
view tree. Each individual write is a separate publish → SwiftUI invalidation pass.

**Why it's costly:** On a chatty source (or during seeking / track changes) a single inbound
update can trigger 4–8 invalidation passes plus animation transactions, multiplying the
cost of §3.1. The diffing work is already done — only the *publishing* is fragmented.

**Fix:** Coalesce the changed fields into a **single value‑type snapshot** published once
(e.g. a `struct NowPlaying: Equatable` exposed as one `@Published`), or at minimum perform
all the assignments inside a single transaction so SwiftUI collapses them into one pass.
Keep `elapsedTime`/`timestampDate` separate from metadata so a position tick doesn't
invalidate views that only show title/artist/artwork.

---

### 4.3 🟠 Per‑line allocations in the stream decoder — **S**

**Where:** `NowPlayingController.swift:278` and `:399`.

```swift
if let date = ISO8601DateFormatter().date(from: dateString) { … }   // :278  — new formatter every update
let decodedObject = try JSONDecoder().decode(T.self, from: data)    // :399  — new decoder every line
```

**Why it's costly:** `ISO8601DateFormatter` is documented as **expensive to instantiate**;
allocating one per update (and a fresh `JSONDecoder` per line) adds avoidable cost to the
hottest media path. Compounds with §3.1.

**Fix:** Hoist both to cached `static let` instances. (Minor, related: the
`JSONLinesPipeHandler` reinstalls a fresh `readabilityHandler` per read via a continuation
loop, `NowPlayingController.swift:374‑415` — a single long‑lived handler that drains complete
lines would allocate less.)

---

### 4.4 🟠 [cross‑checked] `forceUpdate()` on every notch open + raw artwork `Data` compares — **S/M**

**Where:** `models/BoringViewModel.swift:197` (`open()` → `MusicManager.shared.forceUpdate()`);
`MusicManager.swift:204` and `PlaybackState`'s `Equatable`.

- **Every notch open calls `forceUpdate()`** (`:197`). For the AppleScript controllers (the
  default when MediaRemote is deprecated — see §3.1) `forceUpdate → updatePlaybackInfo`
  triggers AppleScript; for YouTube Music it triggers `pollPlaybackState()`, which fires
  several HTTP requests. Since the notch is opened constantly via hover, this turns a
  near‑free UI gesture into a recurring media round‑trip.
- **Raw artwork `Data` is compared on the hot path.** `state.artwork != self.artworkData`
  (`:204`) byte‑compares full album‑art blobs on every update; `PlaybackState` also carries
  `artwork: Data` in its `Equatable`. Large art makes even a trivial elapsed‑time update do
  a multi‑hundred‑KB comparison.

**Fix:**
- Replace the unconditional open‑time refresh with `forceUpdateIfStale(minInterval: ~2 s)`,
  and skip entirely for push/event‑driven controllers whose last update is fresh.
- Compare a cheap **artwork signature** (track ID / URL / hash + byte count) instead of raw
  `Data`; keep `Data` out of `Equatable`.

---

## 5. Tier 3 — Event‑driven (infrequent; low CPU but wasteful)

### 5.1 🟡 Battery: over‑querying, blanket callbacks, and an artificial 1 s drain — **S/M**

**Where:** `BatteryActivityManager.swift:102‑193`; `BatteryStatusViewModel.swift:53‑105`.

- `notifyBatteryChanges()` calls `getBatteryInfo()` (3 IOKit copies:
  `IOPSCopyPowerSourcesInfo` / `…List` / `…GetPowerSourceDescription`) on every power
  notification.
- It then dispatches **all six** `on…Change` callbacks to the main thread **unconditionally**
  (`:157‑165`), even though `checkAndNotify` (`:90‑98`) already knows which single property
  changed. So one event = up to 6 main‑thread closures + 6 potential `@Published` writes.
- `processNextNotification()` drains the queue with a hard‑coded
  `asyncAfter(deadline: .now() + 1.0)` **per event** (`:183`). A first‑run burst of 6 events
  takes **6 seconds** to flush, keeping a chain of main‑thread tasks alive for no reason.
- `BatteryStatusViewModel.handleBatteryEvent` wraps each case in its own `withAnimation`
  (`:57,65,72,82,93,98`), so one event can spawn several animation transactions.

**Why it's low‑priority:** battery events are genuinely rare (a percent every minute or two).
Real CPU impact is small — but the design is wasteful and easy to clean up.

**Fix:** Only dispatch the callback for the property that changed; remove the artificial 1 s
delay (or collapse to a single coalesced async hop); batch the view‑model updates under one
`withAnimation`.

### 5.2 🟡 Volume: cascading CoreAudio listeners + redundant publishes — **S/M**

**Where:** `VolumeManager.swift:172‑233`, `:365‑371`.

Four separate `AudioObjectAddPropertyListenerBlock` callbacks (device, master, per‑channel,
mute) each call `fetchCurrentVolume()`, which loops elements `[main,1,2,3,4]` probing each
channel via `AudioObjectHasProperty`/read (`readVolumeInternal`, `:224‑233`). A single
hardware volume change can fan into all listeners → several CoreAudio round‑trips. `publish`
(`:365‑371`) writes `rawVolume`/`isMuted` **unconditionally** (no equality guard), so even
no‑op changes republish.

**Why it's low‑priority:** only fires when the user actually changes volume/mute. Not an idle
cost.

**Fix:** Detect valid channels **once** at setup and cache them; give the mute listener its
own lightweight read instead of a full `fetchCurrentVolume`; guard `publish` with `!=` checks.

### 5.3 🟡 Calendar: un‑debounced full reload + O(n²) calendar mapping — **S/M**

**Where:** `CalendarManager.swift:45‑54`, `:196‑203`; `CalendarServiceProviding.swift:57‑107`.

- `.EKEventStoreChanged` → `reloadCalendarAndReminderLists()` with **no debounce**
  (`:45‑54`). Any edit to any calendar item fires a full calendar/reminder list reload; rapid
  edits queue multiple reloads.
- `events(from:to:calendars:)` rebuilds the EKCalendar set by linear‑scanning
  `store.calendars(for:)` **for each selected calendar** (`:60‑63`) and then filters again
  inside the access block (`:68‑72`) — repeated `store.calendars(for:)` calls, O(n²) in
  calendar count.
- `setReminderCompleted` re‑fetches **the entire day's events** after toggling a single
  reminder (`:196‑203`).

**Why it's low‑priority:** only triggered by calendar changes / user actions, not idle.

**Fix:** Debounce the `EKEventStoreChanged` handler (~500 ms); build an
`identifier → EKCalendar` dictionary once and reuse it; update the single reminder in place
instead of re‑querying the day.

### 5.4 🟡 Fullscreen detector republishes without dedup — **S**

**Where:** `FullscreenMediaDetection.swift:38‑54`; consumer `BoringViewModel` (the
`CombineLatest3 → withAnimation(.smooth) { hideOnClosed = … }` pipeline).

`updateStatus` assigns `self.fullscreenStatus = newStatus` (`:53`) with no `removeDuplicates`,
so identical states still publish and drive a downstream animated `@Published` write. The
stream is event‑driven (`MacroVisionKit` space changes), so frequency is bounded — but
redundant publishes are free to eliminate. **[cross‑checked]** Worse, the stream is started
unconditionally in `init` (`:21‑23`) and runs **even when `Defaults[.hideNotchOption] ==
.never`**, where fullscreen status is never used. The `.nowPlayingOnly` branch also reaches
into `MusicManager.shared` (`:44`), coupling the detector to the media singleton.

**Fix:** Start the space stream only when `hideNotchOption != .never` (observe
`Defaults.publisher(.hideNotchOption)` to start/stop it — ties into §3.4); guard the
assignment with `if newStatus != fullscreenStatus`; optionally `.debounce` the consumer; and
inject a cheap current‑bundle provider instead of forcing `MusicManager.shared`.

---

## 6. Tier 4 / 5 — Interactive‑only and burst

### 6.1 🔵 Open‑notch `TimelineView` refresh rates — **S**

**Where:** `NotchHomeView.swift:193` (progress slider, **10 Hz**:
`minimumInterval: 0.1`) and `:157` (lyrics, **4 Hz**: `0.25`).

`NotchHomeView` is built **only when the notch is open** (`ContentView.swift:345`), so these
do **not** run while the notch is closed — they are not an idle cost (a subagent initially
claimed otherwise; verified false). Still, while the notch is open and music plays, the
slider redraws 10×/s. A progress bar is smooth at **4–5 Hz**; halving the rate halves that
redraw cost. The lyrics view re‑runs `lyricLine(at:)` every 0.25 s even when the active line
hasn't changed — cheap (binary search, `:491‑507`) but could update only on line change.

**Fix:** Lower the slider interval to ~0.2 s; drive lyrics updates from "current line index
changed" rather than a fixed tick.

### 6.2 🔵 Hover handler churns Tasks and reads `Defaults` per event — **S**

**Where:** `ContentView.swift` `handleHover(_:)` / `.onHover`.

`onHover` fires continuously as the cursor moves near the notch; each call cancels and
recreates a `Task` and reads `Defaults[.minimumHoverDuration]`. Throttle to ~20 ms and read
the setting once.

### 6.3 🔵 SwiftUI `body` does `Defaults[…]` lookups and O(n) screen scans per invalidation — **M**

**Where:** `BoringViewModel.swift` `effectiveClosedNotchHeight` / `chinHeight` (each calls
`NSScreen.screen(withUUID:)`, a linear scan of all displays); many `Defaults[…]` reads
throughout `ContentView.body`.

These re‑evaluate on **every** invalidation. With multiple displays and frequent updates this
adds up. Mirror the hot settings into `@Published` properties via `Defaults.publisher(…)`,
and cache the resolved `NSScreen` (recompute only on screen‑change), so `body` reads cheap
stored values.

### 6.4 ⚪ Display/settings notification storms rebuild windows with no coalescing — **M**

**Where:** `boringNotchApp.swift:256‑263`, `:284‑335`, and the handlers
`screenConfigurationDidChange` (`:457‑475`) / `adjustWindowPosition` (`:477‑543`) /
`setupDragDetectors`.

`NSApplication.didChangeScreenParameters`, `NSWindow.didChangeScreen`, and five custom
settings notifications each **independently** call `cleanupWindows()` /
`adjustWindowPosition()` / `setupDragDetectors()` with no debounce. During a display
reconfiguration (which fires many times) or a sequence of settings toggles, this thrashes —
tearing down and rebuilding `NSHostingView`/windows repeatedly.

**Fix:** Route all of these through a single **coalesced/debounced** "rebuild UI" entry point
(~50–300 ms) so a storm collapses into one rebuild.

### 6.5 🔵 [cross‑checked] HUD media‑key path does heavy work per keystroke — **M**

**Where:** `observers/MediaKeyInterceptor.swift:47‑88` (CG event tap), `:103‑139` /
`:199‑233` (per‑event dispatch); `managers/VolumeManager.swift:37‑101`;
`managers/BrightnessManager.swift` (`setRelative`);
`BoringNotchXPCHelper/BoringNotchXPCHelper.swift:127‑162`.

When `hudReplacement` is on, a `CGEvent` tap intercepts system‑defined events and, for each
volume/brightness keystroke, does real work — and **key‑repeat fires this many times/second**
while a key is held:
- **Volume:** `VolumeManager.increase/decrease` re‑reads the current device, mute state, and
  per‑channel volume from CoreAudio *before* each write (`:37‑101`) — several CoreAudio
  round‑trips per keystroke.
- **Brightness:** `BrightnessManager.setRelative` does an XPC **get** then an XPC **set** —
  two cross‑process round‑trips per keystroke. Inside the helper, each get/set calls
  `dlsym(...)` to resolve `DisplayServicesGet/SetBrightness` **every time**
  (`BoringNotchXPCHelper.swift:144, 154`), with an IOKit registry scan
  (`IOServiceGetMatchingServices`, `:162`) on the fallback path.

**Why it's costly:** user‑triggered, not idle — but holding a volume/brightness key produces
a burst of CoreAudio queries and XPC round‑trips, spiking the main run loop exactly when the
user wants smooth feedback.

**Fix:** Cache the default output device + valid channels (volume) and the resolved
DisplayServices function pointers (brightness) once; for key‑repeat, compute the next step
from the manager's cached `rawVolume`/`rawBrightness` and send only the *set*, publishing
intended state immediately and letting the listener reconcile; coalesce repeats to ≤1
write per ~16–33 ms with a final write on key‑up.

### 6.6 ⚪ [cross‑checked] Shelf / Quick Share / image processing / hot‑path logging — **S/M**

Breadth items from the second analysis, verified as real but mostly **burst / launch** costs
(not steady idle), worth cleaning up:

- **Quick Share discovers providers at launch.** `QuickShareService.shared` is constructed in
  `AppDelegate` (`boringNotchApp.swift:59`) and its `init()` immediately runs
  `discoverAvailableProviders()` (`QuickShareService.swift:29‑33`), which drives an invisible
  sharing picker. Defer until the shelf/share UI is first used (ties into §3.4).
- **Shelf persistence writes the whole JSON file on every item mutation**
  (`Shelf/ViewModels/ShelfStateViewModel.swift:14‑16`). Debounce saves (~250–500 ms, flush on
  terminate); skip when encoded bytes are unchanged.
- **`ShelfItem` resolves security‑scoped bookmarks / reads files inside computed properties**
  (`Shelf/Models/ShelfItem.swift`) that SwiftUI may evaluate repeatedly; cache resolved
  URL/name/icon/type in the item view model. Bound the `ThumbnailService` cache (it's an
  unbounded dictionary) and cap concurrent thumbnail generation.
- **`ImageProcessingService` is `@MainActor`** (`Shelf/Services/ImageProcessingService.swift:34`),
  forcing Vision/Core Image/PDFKit work onto the main actor during image actions; move the
  heavy work to a background actor and reuse a single `CIContext`.
- **`NSLog`/`print` in hot paths** — e.g. `MusicManager.swift:186` logs on every play/pause,
  plus thumbnail/battery/media‑key paths. `NSLog` is comparatively expensive; gate behind a
  debug flag or use `os_log` at the right level.

---

## 7. Things that look expensive but **aren't** (don't chase these)

Verified against the source so the team doesn't spend effort here:

- **"AppleScript runs ~4×/second for now‑playing."** Partly a myth: while MediaRemote works,
  the **default** path is the adapter stream (§1) with no per‑update AppleScript
  (`MusicManager.swift:121‑124`). **But** if MediaRemote is deprecated on the user's macOS,
  `AppleMusicController` is the fallback default (§3.1) and *does* run a large AppleScript per
  `com.apple.Music.playerInfo` notification with no coalescing — so this finding is real **on
  newer/locked‑down macOS**, not on the systems where the adapter still functions. The fix
  (debounce/coalesce + split cheap vs. expensive script reads, cache artwork by track ID) is
  worth doing for those users.
- **DragDetector global monitors are a hot idle loop.** *Mostly* no — **idle cost ≈ 0**: the
  `.leftMouseDragged` global monitor only delivers callbacks **during an active left‑button
  drag** (`DragDetector.swift:64‑90`), not on idle mouse movement, and `hasValidDragContent()`
  is already guarded to run once per drag (`:71`). **Caveat [cross‑checked]:** with
  `showOnAllDisplays` enabled, `setupDragDetectors()` creates **one detector per screen**
  (`boringNotchApp.swift:175‑220`), each installing 3 global monitors — so a 3‑display setup
  has 9 monitors all doing redundant per‑drag work on *every* drag anywhere in the OS, and
  `expandedDragDetection` defaults to `true` (`Constants.swift:165‑173`). Still not an idle
  cost, but worth consolidating into one shared detector keyed by screen UUID, and gating off
  when the shelf feature is disabled.
- **Webcam capture runs in the background.** No. The `AVCaptureSession` is only created/started
  in `startSession()` and fully torn down in `stopSession()` (`WebcamManager.swift:265‑312`);
  it does not run unless the webcam view is shown. **Cheap cleanups when active
  [cross‑checked]:** it uses `.sessionPreset = .high` (`:174`) for a tiny notch preview
  (`.medium`/`.low` cuts ISP/GPU/power); it adds an `AVCaptureVideoDataOutput` with a **nil**
  sample‑buffer delegate (`:177‑181`) that serves no purpose since only a preview layer is
  shown; and several `@Published` properties also call `objectWillChange.send()` in `didSet`
  (`:13‑36`), **double‑firing** SwiftUI notifications. All worth fixing, none an idle cost.
- **MusicVisualizer leaks/accumulates animations.** No unbounded leak: re‑adding with the same
  key `"scaleY"` (`:85`) **replaces** the prior animation. The cost is the 0.3 s timer + Core
  Animation work (§3.2), not a leak.
- **`visualizer.metal` Metal shader.** There are **no** `MTKView` / `CAMetalLayer` / Metal
  pipeline references in the Swift code — the shader appears to be **unused/dead code** and is
  not a runtime cost.
- **YouTube Music 2 s polling timer** (`YouTubeMusicController.swift:325`). Only active when
  YouTube Music is the selected source *and* its WebSocket is unavailable — not the default
  path. (If pursued: prefer the existing WebSocket; back off the fallback interval.)

---

## 8. Prioritized roadmap

Ordered by **(idle‑CPU impact ÷ effort)** — do the top items first.

| # | Finding | Tier | Effort | Expected effect |
|---|---------|------|--------|-----------------|
| 1 | Add `--debounce=200` to the adapter stream (§3.1) | 🔴 | **S** | Coalesces the chattiest media path upstream of all Swift work. |
| 2 | Pause closed‑notch visualizer when window occluded / display asleep / Low Power (§3.2) | 🔴 | **M** | Removes the main always‑on playback cost. |
| 3 | Lottie: Core Animation engine + bundle asset locally (§3.2) | 🔴 | **S/M** | Big cut if Lottie is the active visualizer; removes a network fetch. |
| 4 | Fix the leaked `AnimatedFace` timer (§3.3) | 🔴 | **S** | Stops a forever‑growing set of 3 s wake‑ups. |
| 5 | Make singleton `init`s side‑effect‑free; gate subsystem `start()` on feature flags/visibility (§3.4) | 🔴 | **M/L** | Stops booting media/CoreAudio/IOKit/fullscreen/webcam/share at idle. Biggest *structural* idle win. |
| 6 | Replace `averageColor` pixel loop with 1×1 downsample / `CIAreaAverage` + cache (§4.1) | 🟠 | **S** | Per‑track CPU spike → ~free; pattern already in‑file. |
| 7 | Cache `ISO8601DateFormatter` / `JSONDecoder` (§4.3) | 🟠 | **S** | Trims the hot decode path. |
| 8 | Coalesce `updateFromPlaybackState` publishes into one snapshot; drop raw artwork `Data` compares (§4.2, §4.4) | 🟠 | **M** | Fewer SwiftUI invalidations + no big‑blob byte compares per update. |
| 9 | `forceUpdateIfStale` instead of `forceUpdate()` on every open (§4.4) | 🟠 | **S** | Stops a media round‑trip on every hover‑open. |
| 10 | Gate the fullscreen detector on `hideNotchOption != .never` + equality guard (§5.4) | 🟡 | **S** | Removes an always‑on space stream when hiding is off. |
| 11 | Coalesce display/settings rebuild notifications (§6.4) | ⚪ | **M** | Kills window‑rebuild thrash on display changes. |
| 12 | Coalesce HUD media‑key writes; cache CoreAudio device/channels + DisplayServices pointers (§6.5) | 🔵 | **M** | Smooth volume/brightness key‑repeat without per‑event CoreAudio/XPC storms. |
| 13 | Mirror hot `Defaults`/screen lookups out of `body` (§6.3) | 🔵 | **M** | Cheaper re‑renders across the board. |
| 14 | Battery / Volume / Calendar cleanups (§5.1–5.3) | 🟡 | **S/M** | Low CPU, but correctness + tidiness wins. |
| 15 | Slider 10 Hz → ~5 Hz; lyrics update on line change (§6.1) | 🔵 | **S** | Halves open‑notch redraw while playing. |
| 16 | Defer Quick Share discovery; debounce shelf persistence; move image processing off main actor (§6.6) | ⚪ | **S/M** | Lower launch + burst CPU. |

---

## 9. How to measure (before/after)

To confirm impact rather than guess:

1. **Activity Monitor → % CPU**, three scenarios, each ~60 s:
   (a) idle, notch closed, nothing playing; (b) music playing, notch closed; (c) notch open
   with music. Record both `boring.notch` **and** the child **`perl`** process (it shows
   separately).
2. **Instruments → Time Profiler** during (b) to attribute samples to
   `updateFromPlaybackState`, Core Animation (visualizer), and `averageColor`.
3. **`powermetrics --samplers tasks`** (sudo) to watch *wake‑ups/sec* — the cleanest proxy
   for "preventing CPU idle." Items §3.1–3.3 should drop this number the most.
4. Re‑run after each roadmap item; the table in §8 predicts where the largest deltas should
   appear (items 1–4).

---

### Appendix — file reference index

| Subsystem | Key files |
|-----------|-----------|
| Media stream | `MediaControllers/NowPlayingController.swift`, `mediaremote-adapter/mediaremote-adapter.pl`, `managers/MusicManager.swift`, `helpers/MediaChecker.swift`, `models/PlaybackState.swift` |
| Media (opt‑in / fallback) | `MediaControllers/AppleMusicController.swift`, `MediaControllers/SpotifyController.swift`, `MediaControllers/YouTube Music Controller/`, `models/Constants.swift` (`defaultMediaController`) |
| Color / artwork | `extensions/NSImage+Extensions.swift` |
| Visualizers | `ContentView.swift` (451‑468), `components/Music/MusicVisualizer.swift`, `components/Music/LottieAnimationView.swift`, `components/AnimatedFace.swift` |
| Open‑notch UI | `components/Notch/NotchHomeView.swift` |
| System managers | `managers/BatteryActivityManager.swift`, `models/BatteryStatusViewModel.swift`, `managers/VolumeManager.swift`, `managers/BrightnessManager.swift`, `managers/CalendarManager.swift`, `Providers/CalendarServiceProviding.swift`, `managers/WebcamManager.swift` |
| HUD / media keys / XPC | `observers/MediaKeyInterceptor.swift`, `BoringNotchXPCHelper/BoringNotchXPCHelper.swift` |
| Shelf / share / images | `components/Shelf/ViewModels/ShelfStateViewModel.swift`, `components/Shelf/Models/ShelfItem.swift`, `components/Shelf/Services/ThumbnailService.swift`, `components/Shelf/Services/QuickShareService.swift`, `components/Shelf/Services/ImageProcessingService.swift` |
| Windows / lifecycle | `boringNotchApp.swift`, `models/BoringViewModel.swift` (eager singletons, `open()`), `ContentView.swift` (eager singletons), `observers/FullscreenMediaDetection.swift`, `observers/DragDetector.swift` |
