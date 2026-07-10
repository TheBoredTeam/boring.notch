# Boring Notch backend CPU analysis

## Scope

This began as a static backend/runtime analysis of the repository. The impact ranking below is based on code paths, default feature state, and how often each path can run while the notch is idle, closed, hovered, or actively used. The implementation described below has been compiled, but it has not yet been measured with Instruments, so no numerical CPU reduction is claimed.

Update note: this version has been revised after comparing it with `notch_analysis.md`. I incorporated the findings that were both source-backed and relevant to compute reduction, and I narrowed a few earlier statements where the other analysis correctly distinguished idle costs from interaction-only costs.

## Implementation update — 2026-07-10

The first performance pass has now been implemented. It addresses the highest-impact low- and medium-risk items while preserving the current UI and feature behavior.

Completed changes:

1. **MediaRemote stream coalescing:** `NowPlayingController` now starts the adapter with `--debounce=200`, so notification bursts are collapsed before JSON decoding, Combine publication, and SwiftUI invalidation.
2. **Hot-path allocation reduction:** `NowPlayingController` reuses one `ISO8601DateFormatter`, and `JSONLinesPipeHandler` reuses one `JSONDecoder` instead of allocating them for every stream update.
3. **AppleScript controller coalescing:** Apple Music and Spotify distributed-notification bursts are debounced by 200 ms before running their comparatively expensive playback-info AppleScripts.
4. **Stale-aware open refresh:** `BoringViewModel.open()` now calls `MusicManager.forceUpdateIfStale(maxAge:)`. Repeated hover-open events no longer launch AppleScript or YouTube Music HTTP refreshes while media state is fresh.
5. **Constant-cost artwork change detection:** Raw artwork `Data` equality checks were replaced with a byte-count plus fixed-sample signature. `PlaybackState.Equatable` and `MusicManager` no longer scan entire artwork blobs to detect UI changes.
6. **Fewer redundant publications:** `MusicManager` now avoids assigning `timestampDate` when the incoming value is unchanged.
7. **Efficient artwork color extraction:** The full-resolution bitmap allocation and per-pixel CPU loop were replaced with `CIAreaAverage` rendered to one pixel. The image helpers also share a single `CIContext` and color space.
8. **Visualizer lifecycle gating:** Both the spectrum and Lottie animation pause when their window is occluded, the application is hidden, or Low Power Mode is enabled. The spectrum timer changed from 0.3 seconds to 0.4 seconds and now has 0.1 seconds of timer tolerance.
9. **Blink timer leak fixed:** `MinimalFaceFeatures` now uses a cancellable SwiftUI `.task` rather than an unmanaged repeating `Timer`, so disappearing and reappearing no longer accumulates permanent wake-ups.
10. **Fullscreen detector lifecycle:** `FullscreenMediaDetector` starts and stops with the `hideNotchOption` setting, stops completely for `.never`, and publishes only when the computed fullscreen dictionary actually changes.
11. **Lazy Quick Share discovery:** Quick Share provider discovery was removed from singleton/AppDelegate initialization. It now runs on first display of the shelf sharing view or settings and prevents duplicate concurrent discovery.
12. **Side-effect-free media default:** `Defaults.Keys.mediaController` now has a static `.nowPlaying` default. The asynchronous compatibility check in `MusicManager` still falls back to Apple Music when required, without constructing `MusicManager.shared` merely to initialize defaults.

Verification:

- `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/boringNotchDerivedData CODE_SIGNING_ALLOWED=NO build` succeeds.
- `git diff --check` succeeds.
- The build retains an existing linker warning because `MediaRemoteAdapter.framework` was built for macOS 15 while the app deployment target is macOS 14.

Still recommended but not yet implemented:

- Consolidate `MusicManager`'s many `@Published` fields into metadata and timeline snapshots to reduce SwiftUI invalidation fan-out.
- Add explicit start/stop lifecycle APIs for the remaining eagerly initialized battery, volume, brightness, and webcam services.
- Replace per-screen global drag monitors with one shared expanded-drag detector.
- Coalesce CoreAudio and brightness XPC work during media-key repeats.
- Debounce shelf persistence and calendar reloads, bound thumbnail work, and move remaining image-processing operations off `@MainActor`.
- Bundle the default Lottie visualizer locally rather than fetching it from a remote URL.
- Measure idle, closed-notch playback, and open-notch playback with Instruments and `powermetrics` to quantify the improvement.

The detailed findings below are retained as the **pre-implementation baseline**. Statements and code excerpts describing missing debounce, full artwork comparisons, eager Quick Share discovery, unmanaged face timers, or unconditional fullscreen monitoring should be read together with the implementation update above.

## Executive summary

The main CPU risk is not one obvious tight loop. It is many small always-on subsystems being created eagerly, plus several continuous or bursty update paths that do too much work per event:

1. `ContentView` eagerly instantiates `MusicManager`, `BatteryStatusViewModel`, `BrightnessManager`, `VolumeManager`, `WebcamManager`, and the shared coordinator for every notch window. This makes "closed notch at idle" more expensive than it needs to be.
2. The media subsystem is the highest-risk backend path. It launches an external Perl/MediaRemote adapter, decodes JSON stream updates, base64-decodes artwork, compares `Data`, publishes many separate `@Published` properties, and can run AppleScript/HTTP refreshes on hover/open.
3. Fullscreen detection starts immediately through `FullscreenMediaDetector.shared` and keeps a MacroVisionKit space stream alive even when the user's hide behavior could make it unnecessary.
4. The closed-notch music live activity can animate continuously while music plays. `AudioSpectrumView` uses a repeating timer, and the alternate Lottie visualizer loops indefinitely.
5. The optional idle face starts an unmanaged repeating timer on every appearance.
6. Artwork color extraction scans full-resolution album art on the CPU when the colored spectrogram is enabled.
7. Expanded shelf drag detection installs global mouse monitors per screen. It is not an idle loop, but it multiplies callbacks during any left-button drag, including drags outside the app.
8. HUD replacement uses a CG event tap and then performs relatively heavy CoreAudio/XPC brightness work per media-key event. This is user-triggered rather than idle, but it can spike during key repeats.
9. Shelf, thumbnail, Quick Share, calendar, webcam, and image-processing paths are mostly burst costs, but several are still initialized or run earlier than necessary.

The best CPU reduction plan is:

1. Make singleton initializers cheap and add explicit `start()` / `stop()` lifecycle methods.
2. Gate always-on managers by feature flags and visible state.
3. Pause or remove continuous closed-notch animation when not visible, occluded, or in Low Power Mode.
4. Throttle/coalesce media, fullscreen, drag, CoreAudio, and XPC update streams.
5. Remove large `Data` comparisons and batch published state changes.
6. Replace full-image CPU scans with downsampled/GPU-assisted artwork analysis.
7. Move blocking I/O and image work off `@MainActor`.

## Highest-impact findings

### 1. Runtime services are eagerly constructed

Evidence:

- `ContentView` creates observed singletons on view construction: `WebcamManager.shared`, `MusicManager.shared`, `BatteryStatusViewModel.shared`, `BrightnessManager.shared`, and `VolumeManager.shared` in `boringNotch/ContentView.swift:17-25`.
- `BoringViewModel` also constructs `FullscreenMediaDetector.shared` and `WebcamManager.shared` in `boringNotch/models/BoringViewModel.swift:13-40`.
- `AppDelegate` constructs `QuickShareService.shared` as a stored property in `boringNotch/boringNotchApp.swift:57-60`.
- `QuickShareService.init()` immediately runs provider discovery in `boringNotch/components/Shelf/Services/QuickShareService.swift:29-33`.
- `Defaults.Keys.defaultMediaController` reads `MusicManager.shared.isNowPlayingDeprecated` in `boringNotch/models/Constants.swift:192-199`, which risks pulling the media subsystem into defaults initialization.

Why this costs CPU:

- The app presents a small notch UI, but the backend starts music, battery, brightness, volume, fullscreen, webcam availability, and share-provider work early.
- If `showOnAllDisplays` is enabled, `AppDelegate.adjustWindowPosition` creates a `BoringViewModel` and `ContentView` per screen, multiplying SwiftUI observation and some runtime work (`boringNotch/boringNotchApp.swift:477-510`).
- Several managers perform real work in `init`: `MusicManager` runs a MediaRemote deprecation process, `VolumeManager` registers CoreAudio listeners and fetches volume, `BatteryStatusViewModel` starts battery monitoring, `WebcamManager` checks camera availability, `QuickShareService` discovers providers.

How to fix:

- Move expensive work out of singleton initializers. Initializers should only allocate fields.
- Add idempotent lifecycle APIs:
  - `MusicManager.startIfNeeded()` / `stopIfIdle()`
  - `FullscreenMediaDetector.startIfNeeded()` / `stop()`
  - `QuickShareService.discoverAvailableProvidersIfNeeded()`
  - `WebcamManager.refreshAvailabilityIfNeeded()`
- Start managers from `AppDelegate` or a backend `FeatureRuntimeCoordinator` based on current defaults, not from `ContentView` construction.
- Keep backend-only behavior by making existing `shared` access cheap. Frontend code can still observe the managers, but observation should not start expensive listeners.
- Remove the `MusicManager.shared` dependency from `Defaults.Keys.defaultMediaController`. Use a static default such as `.nowPlaying`, then migrate/fallback after the async deprecation check completes.

Expected result:

- Lower idle CPU because creating windows/views no longer starts media, share, fullscreen, webcam, and battery work by default.
- Less multi-display amplification.

### 2. Media subsystem does too much work per update

Evidence:

- `MusicManager.init()` starts `MediaChecker.checkDeprecationStatus()` in a task, then creates the active controller in `boringNotch/managers/MusicManager.swift:71-93`.
- `MediaChecker` launches `/usr/bin/perl` and a test client, then waits up to 10 seconds in `boringNotch/helpers/MediaChecker.swift:18-66`.
- `NowPlayingController` launches `/usr/bin/perl mediaremote-adapter.pl ... stream` in `boringNotch/MediaControllers/NowPlayingController.swift:190-213`.
- `NowPlayingController.processJSONStream()` continuously reads JSON lines from the adapter in `boringNotch/MediaControllers/NowPlayingController.swift:219-226`.
- `NowPlayingController.handleAdapterUpdate()` creates a new `PlaybackState`, base64-decodes artwork, constructs a new `ISO8601DateFormatter`, and publishes state in `boringNotch/MediaControllers/NowPlayingController.swift:229-297`.
- `MusicManager.updateFromPlaybackState()` can update many separate published fields and compare artwork `Data` in `boringNotch/managers/MusicManager.swift:182-292`.
- `BoringViewModel.open()` calls `MusicManager.shared.forceUpdate()` every time the notch opens in `boringNotch/models/BoringViewModel.swift:192-198`.

Why this costs CPU:

- The external adapter process is event-driven, but every emitted line crosses process boundaries, is converted to text, decoded as JSON, transformed to `PlaybackState`, then fanned out through Combine/SwiftUI.
- Artwork is the heaviest field. `PlaybackState.Equatable` compares `artwork` `Data` in `boringNotch/models/PlaybackState.swift:33-46`, and `MusicManager` separately compares `state.artwork != self.artworkData` in `boringNotch/managers/MusicManager.swift:197-205`. Large album art can make otherwise small state updates expensive.
- `MusicManager` publishes `songTitle`, `artistName`, `albumArt`, `isPlaying`, `album`, `isPlayerIdle`, `avgColor`, `bundleIdentifier`, `songDuration`, `elapsedTime`, `timestampDate`, `playbackRate`, shuffle/repeat/volume/favorite fields separately. A single media event can trigger many object changes.
- Hover/open can force media refreshes. With Apple Music or Spotify controllers this means AppleScript; with YouTube Music it can mean multiple HTTP calls.

How to fix:

- Add stale-aware force updates:
  - Replace `forceUpdate()` on every open with `forceUpdateIfStale(minInterval: 2.0)` or `forceUpdate(reason:)`.
  - Skip if the active controller is push/event driven and the last state update is fresh.
- Batch media state:
  - Introduce a single `@Published private(set) var presentationState`.
  - Derive UI fields from it instead of publishing each field separately.
  - At minimum, use a local diff and publish only once per input state.
- Stop comparing raw artwork data:
  - Add `artworkSignature` or `artworkID` to `PlaybackState`.
  - Compare URL, media item ID, MIME plus byte count/hash, or adapter track identifier.
  - Keep `Data` out of `PlaybackState.Equatable`, or compare only a cheap signature.
- Reuse expensive helpers:
  - Make `ISO8601DateFormatter` static in `NowPlayingController`.
  - Reuse `JSONDecoder` in `JSONLinesPipeHandler`.
- Throttle adapter events:
  - The bundled adapter supports `stream --debounce=N`. Current args are only `["stream"]`.
  - Add a small debounce such as `--debounce=100` or `--debounce=250`.
  - Test responsiveness for play/pause and track changes; this is likely a good CPU/responsiveness tradeoff.
- Split artwork from timeline updates:
  - Decode and publish artwork only when title/artist/album/bundle or artwork signature changes.
  - Do not carry artwork through every playback position/state update.
- Avoid work while idle:
  - If there is no active media app and the notch is closed, keep media state frozen and do not poll.
  - Resume on media-app launch notification, media key command, or notch open after a stale interval.

Expected result:

- Fewer JSON/Combine/SwiftUI updates.
- Lower CPU spikes from artwork updates.
- Less work when the notch is repeatedly opened by hover.

### 3. Closed-notch visualizers can animate continuously during playback

Evidence:

- `ContentView.MusicLiveActivity()` is shown while the notch is closed when music is playing or recently active in `boringNotch/ContentView.swift:290-292`.
- In that closed live activity, `useMusicVisualizer` selects `AudioSpectrumView(isPlaying:)` in `boringNotch/ContentView.swift:451-464`.
- `AudioSpectrum.startAnimating()` schedules a repeating `Timer` every 0.3 seconds and creates `CABasicAnimation` objects for the bars in `boringNotch/components/Music/MusicVisualizer.swift:57-87`.
- If `useMusicVisualizer` is false, `LottieAnimationContainer()` is shown instead in `boringNotch/ContentView.swift:465-468`.
- The default Lottie branch loads a remote animation URL and loops forever in `boringNotch/components/Music/LottieAnimationView.swift:11-18`.

Why this costs CPU:

- This path runs while the notch is closed and visible, so it affects the exact "music playing in the background" case users are likely to notice.
- `AudioSpectrumView` is decorative random motion, not actual audio analysis, but it still wakes every 0.3 seconds and asks Core Animation to animate layers.
- Lottie can be more expensive than the timer path because vector animation may rasterize continuously, depending on rendering engine and asset complexity.
- Neither branch is gated on window occlusion, display sleep, Space visibility, or Low Power Mode.

How to fix:

- Add a backend visibility gate for visualizer activity:
  - pause when `NSWindow.occlusionState` does not contain `.visible`,
  - pause when the screen is locked/asleep,
  - pause when `ProcessInfo.processInfo.isLowPowerModeEnabled`,
  - pause when the notch is hidden due to fullscreen rules.
- For `AudioSpectrumView`, keep the view but stop its timer when not visible. Optionally reduce the tick interval to 0.4-0.5 seconds.
- For Lottie, bundle the default asset locally instead of fetching from `lottiefiles.com`, and configure the Core Animation rendering engine if the Lottie version supports it.
- Consider a static waveform/spectrum in the closed notch and reserve motion for the open notch.

Expected result:

- Lower steady CPU while music is playing and the notch is closed.
- Fewer wake-ups per second and less render-server/main-thread activity.

### 4. Optional idle face starts a leaked repeating timer

Evidence:

- `BoringFaceAnimation()` creates `MinimalFaceFeatures()` when the player is idle and `showNotHumanFace` is enabled in `boringNotch/ContentView.swift:293-295` and `boringNotch/ContentView.swift:367-386`.
- `MinimalFaceFeatures.onAppear` calls `startBlinking()` in `boringNotch/components/AnimatedFace.swift:43-45`.
- `startBlinking()` calls `Timer.scheduledTimer(withTimeInterval: 3, repeats: true)` but does not store or invalidate the timer in `boringNotch/components/AnimatedFace.swift:48-59`.

Why this costs CPU:

- This feature is off by default, so it is not a default idle CPU source.
- When enabled, every appearance can leave another repeating timer on the run loop.
- Each leaked timer wakes every three seconds and schedules SwiftUI animations even after the face disappears.

How to fix:

- Store the timer in `@State` or move the blinking behavior into a small `ObservableObject`.
- Guard against double-start.
- Invalidate on `.onDisappear`.
- Prefer `Task.sleep` with cancellation tied to view lifecycle if staying in SwiftUI.

Expected result:

- Prevents an accumulating source of periodic wake-ups for users who enable the face.

### 5. Average artwork color scans full-resolution images on the CPU

Evidence:

- `MusicManager.updateAlbumArt(newAlbumArt:)` calls `calculateAverageColor()` when `Defaults[.coloredSpectrogram]` is true in `boringNotch/managers/MusicManager.swift:556-583`.
- `NSImage.averageColor(completion:)` draws the full `CGImage` into a full-size RGBA bitmap, then loops over every pixel in `boringNotch/extensions/NSImage+Extensions.swift:19-106`.
- The same extension already has a more efficient `getBrightness()` implementation using `CIFilter.areaAverage` and a 1x1 render in `boringNotch/extensions/NSImage+Extensions.swift:108-136`.

Why this costs CPU:

- Album artwork can be hundreds or thousands of pixels square. The current method is O(width x height), allocates a large bitmap, and sums every pixel.
- It runs on a background queue, so it may not block the UI, but it still burns CPU on every artwork change.
- The result is used as a rough tint color, so full-resolution precision is unnecessary.

How to fix:

- Replace `averageColor` with a 1x1 downsample or `CIAreaAverage`.
- Reuse a shared `CIContext` rather than constructing one per call.
- Cache average colors by artwork signature, track ID, or image-data hash.
- Cancel stale average-color work when a newer artwork update arrives.

Expected result:

- Reduces per-track-change CPU spikes from potentially millions of pixel operations to a tiny constant-size operation.

### 6. Apple Music and Spotify controllers use AppleScript too often when selected

Evidence:

- `AppleMusicController` listens to `com.apple.Music.playerInfo` and runs `updatePlaybackInfo()` for every notification in `boringNotch/MediaControllers/AppleMusicController.swift:43-52`.
- `AppleMusicController.updatePlaybackInfo()` executes one large AppleScript that reads player state, track fields, artwork data, volume, and favorite state in `boringNotch/MediaControllers/AppleMusicController.swift:131-198`.
- `SpotifyController` listens to `com.spotify.client.PlaybackStateChanged` and runs `updatePlaybackInfo()` in `boringNotch/MediaControllers/SpotifyController.swift:49-59`.
- `SpotifyController.updatePlaybackInfo()` executes AppleScript, publishes state, and may fetch artwork over the network in `boringNotch/MediaControllers/SpotifyController.swift:99-160`.

Why this costs CPU:

- These controllers are opt-in alternatives. The default path is `NowPlayingController`, so this is not the default idle media cost.
- AppleScript has high fixed overhead. It wakes the target app, marshals Apple events, and returns descriptors.
- Notifications can arrive in bursts. The current code does not debounce, serialize, or collapse duplicate updates.
- Apple Music fetches artwork data as part of every script result, even when only play/pause or elapsed time changed.

How to fix:

- Add an `UpdateCoalescer` for script controllers:
  - Keep one in-flight `updatePlaybackInfo()`.
  - If another notification arrives while in flight, set `needsRefresh = true`.
  - Debounce bursts by 100-250 ms.
- Split cheap and expensive script reads:
  - Cheap update: playing, elapsed, volume.
  - Expensive update: title, artist, album, artwork, favorite.
  - Run the expensive update only when a track identifier or metadata changed.
- Cache artwork by track identity.
- For Spotify artwork, store `lastArtworkURL` and also retain failed URL timestamps to avoid repeated failed fetches.
- Consider using one controller strategy when possible:
  - Prefer the MediaRemote stream for general now-playing state.
  - Use AppleScript only for actions not supported by MediaRemote, such as app-specific volume/favorite.

Expected result:

- Lower CPU during playback changes.
- Lower latency spikes from AppleScript.

### 7. YouTube Music combines WebSocket, polling, and repeated HTTP calls when selected

Evidence:

- The controller sets `updateInterval` to 2 seconds in `boringNotch/MediaControllers/YouTube Music Controller/YouTubeMusicModels.swift:17-22`.
- `startPeriodicUpdates()` schedules a repeating timer when WebSocket is unavailable in `boringNotch/MediaControllers/YouTube Music Controller/YouTubeMusicController.swift:320-330`.
- `updatePlaybackInfo()` authenticates, fetches `/song`, then fetches `/like-state` in `boringNotch/MediaControllers/YouTube Music Controller/YouTubeMusicController.swift:106-142`.
- `pollPlaybackState()` calls repeat, shuffle, and full playback info in sequence in `boringNotch/MediaControllers/YouTube Music Controller/YouTubeMusicController.swift:337-345`.
- Artwork fetches are started after state changes without a `lastArtworkURL` guard in `boringNotch/MediaControllers/YouTube Music Controller/YouTubeMusicController.swift:437-455`.

Why this costs CPU:

- This is also an opt-in media controller, not the default path.
- If WebSocket connection fails, the app polls every 2 seconds. Each poll can involve auth, JSON parsing, playback state, and like state.
- `forceUpdate()` uses `pollPlaybackState()` for this controller, so opening the notch can trigger multiple HTTP requests.
- Repeated artwork URL fetches can be restarted when state changes for reasons unrelated to artwork.

How to fix:

- Poll only as a fallback and back off:
  - 2 seconds while playing and visible/open.
  - 10-30 seconds while paused or notch closed.
  - Exponential backoff when the local server is unavailable.
- Use a cancellable task loop instead of `Timer.scheduledTimer`; tie it to controller lifecycle.
- Fetch like state only when the current track changes or the favorite button is visible/interacted with.
- Add `lastArtworkURL` and `lastArtworkFetchFailedAt`.
- Change `forceUpdate()` for YouTube Music to call only `updatePlaybackInfo()` unless shuffle/repeat are stale or visible.
- Do not cancel `appStateObserver` on app termination. `handleAppTerminated()` currently cancels it in `boringNotch/MediaControllers/YouTube Music Controller/YouTubeMusicController.swift:180-197`; that is a lifecycle bug and can prevent future launches from restarting the controller.

Expected result:

- Less network and JSON work during WebSocket outages.
- Less CPU on hover/open.

### 8. Fullscreen media detection is always started and republishes whole dictionaries

Evidence:

- `FullscreenMediaDetector.shared` starts monitoring in its private initializer in `boringNotch/observers/FullscreenMediaDetection.swift:21-35`.
- It consumes `FullScreenMonitor.shared.spaceChanges()` and publishes a new `[String: Bool]` dictionary for each stream update in `boringNotch/observers/FullscreenMediaDetection.swift:29-54`.
- `BoringViewModel` creates the detector as an observed object in `boringNotch/models/BoringViewModel.swift:13-15`, then each view model subscribes to `detector.$fullscreenStatus` in `boringNotch/models/BoringViewModel.swift:72-103`.

Why this costs CPU:

- Space/window/fullscreen monitoring can be expensive on macOS because it usually depends on workspace, window, or private space notifications.
- The detector runs even when `Defaults[.hideNotchOption] == .never`, where fullscreen status should not matter.
- `updateStatus` assigns `fullscreenStatus` without checking equality. Downstream `removeDuplicates()` reduces some work per `BoringViewModel`, but the detector still publishes.
- With multiple displays/windows, every `BoringViewModel` runs the Combine pipeline.

How to fix:

- Do not start the stream in `init`.
- Start only when `hideNotchOption != .never`.
- Observe `Defaults.publisher(.hideNotchOption)` and start/stop the stream when the setting changes.
- Before assigning, guard:
  - `if fullscreenStatus != newStatus { fullscreenStatus = newStatus }`
- Throttle bursty space changes, for example 100-250 ms.
- For `.nowPlayingOnly`, avoid forcing `MusicManager.shared` inside the detector if the music subsystem is not otherwise running. Inject a lightweight current-bundle provider or cached string.
- Consider moving the per-screen hide calculation into the detector and publish only `screenUUID -> shouldHide`, not raw fullscreen state plus separate per-view-model Combine work.

Expected result:

- Lower idle CPU when fullscreen hiding is disabled.
- Less Combine churn on space changes.

### 9. Expanded drag detection uses per-screen global mouse monitors

Evidence:

- `expandedDragDetection` defaults to `true` in `boringNotch/models/Constants.swift:165-173`.
- `AppDelegate.setupDragDetectors()` creates one `DragDetector` per screen when `showOnAllDisplays` is enabled in `boringNotch/boringNotchApp.swift:175-220`.
- Each `DragDetector` installs three global monitors: left mouse down, left mouse dragged, and left mouse up in `boringNotch/observers/DragDetector.swift:51-100`.
- The dragged monitor checks the drag pasteboard change count on every left-drag event in `boringNotch/observers/DragDetector.swift:64-90`.

Why this costs CPU:

- Global monitors receive matching mouse events outside the app. This is not an idle loop, because the drag callback only runs during active left-button drags.
- With multiple displays, monitors multiply. Three screens means nine global monitor callbacks.
- During any left-drag operation, the app executes pasteboard and region logic even if the user is dragging in another app and never approaches the notch.

How to fix:

- Replace per-screen detectors with one shared `DragDetectorManager`.
  - Keep one mouseDown, one mouseDragged, one mouseUp monitor.
  - Store an array/dictionary of notch regions by screen UUID.
- Cache the drag classification once the pasteboard change count proves content is being dragged, then avoid repeated pasteboard reads during the same drag.
- Throttle dragged processing to display-rate or lower, for example every 16-33 ms.
- Disable expanded detection when:
  - shelf feature is off,
  - notch is open and already has a drop target,
  - app is hidden/screen locked and not showing on lock screen,
  - there are no eligible screens.
- Consider using local SwiftUI/AppKit drop targets for the closed notch area before global monitoring. The existing `ContentView.dragDetector` already has an `.onDrop` path in `boringNotch/ContentView.swift:492-503`; global detection should only handle the expanded "open on drag near notch" behavior.

Expected result:

- Lower CPU during unrelated drag operations.
- Large improvement on multi-display setups.

### 10. HUD replacement and media-key handling do heavy work per key repeat

Evidence:

- `MediaKeyInterceptor` creates a CG event tap for system-defined events in `boringNotch/observers/MediaKeyInterceptor.swift:47-88`.
- It converts each matching `CGEvent` to `NSEvent`, parses media key data, and dispatches actions in `boringNotch/observers/MediaKeyInterceptor.swift:103-139`.
- Volume key handlers call `VolumeManager.shared.increase/decrease`, and brightness key handlers call XPC-backed managers in `boringNotch/observers/MediaKeyInterceptor.swift:199-233`.
- `VolumeManager.increase/decrease/setAbsolute` repeatedly read current device, mute state, volume channels, write volume, then publish in `boringNotch/managers/VolumeManager.swift:37-101`.
- `BrightnessManager.setRelative` asks the XPC helper for current brightness and then sends a set request in `boringNotch/managers/BrightnessManager.swift:30-42`.
- The XPC helper resolves DisplayServices symbols with `dlsym` on each brightness get/set and scans IORegistry in fallback paths in `BoringNotchXPCHelper/BoringNotchXPCHelper.swift:109-158`.

Why this costs CPU:

- Key repeat can produce many events per second.
- Volume adjustment performs several CoreAudio property calls for each event.
- Brightness adjustment performs at least one XPC round trip for current brightness and another for setting brightness.
- The helper repeats dynamic symbol lookup and can repeat display-service discovery.

How to fix:

Volume:

- Cache the default output device ID and supported channel elements.
- On default output device change, rebuild listeners and channel cache.
- Use a dedicated serial dispatch queue for CoreAudio listener blocks.
- Coalesce volume/mute listener callbacks with a short debounce, for example 20-50 ms.
- For key-repeat writes, use the manager's cached `rawVolume` as the starting point instead of reading from CoreAudio first on every step.
- Publish intended state immediately, then let the CoreAudio listener reconcile.
- Remove property listeners in deinit or stop lifecycle.

Brightness:

- Cache DisplayServices function pointers in the helper once.
- Cache the `io_service_t` or a display-service resolver per display and invalidate on display changes.
- For key-repeat writes, compute from cached `rawBrightness` and send only set requests.
- Coalesce repeated brightness writes so holding the key sends at most one XPC set every 16-33 ms, plus a final set when key repeat ends.
- Avoid wrapping entire XPC operations in `Task { @MainActor in ... }`; only publish on main after the async call.

Event tap:

- Keep the event tap disabled unless `hudReplacement` is true and accessibility is authorized.
- This is already mostly true in `BoringViewCoordinator`, but make the start/stop path explicit and idempotent.
- Avoid `print`/`NSLog` inside frequent event paths such as feedback sound playback.

Expected result:

- Lower spikes while holding volume/brightness keys.
- Less main-run-loop pressure.

### 11. Battery monitoring is mostly event-driven but publishes more than necessary

Evidence:

- `BatteryActivityManager` uses `IOPSNotificationCreateRunLoopSource`, so it is not polling in `boringNotch/managers/BatteryActivityManager.swift:68-79`.
- On every power notification it calls all optional callbacks with all current values, even if only one field changed, in `boringNotch/managers/BatteryActivityManager.swift:156-165`.
- It also enqueues separate delayed events with a one-second delay in `boringNotch/managers/BatteryActivityManager.swift:168-193`.
- `BatteryStatusViewModel` shows expanding HUD notifications for several battery events in `boringNotch/models/BatteryStatusViewModel.swift:53-128`.

Why this costs CPU:

- This is not likely the primary idle CPU source.
- It can still trigger unnecessary SwiftUI updates and animations on each power notification.
- Initial setup can generate multiple events.

How to fix:

- Only call per-field callbacks for fields that changed.
- Suppress initial notifications unless the UI explicitly needs them.
- Batch multiple battery changes from one IOKit notification into one published state update.
- Remove excessive `print` logging in battery event handlers.

Expected result:

- Smaller bursts on power-source changes.

### 12. Webcam preview uses a heavier capture setup than the notch needs

Evidence:

- `WebcamManager` checks camera availability in `init` in `boringNotch/managers/WebcamManager.swift:63-68`.
- `setupCaptureSession` uses `.high` preset and adds an `AVCaptureVideoDataOutput` with a nil sample buffer delegate in `boringNotch/managers/WebcamManager.swift:131-183`.
- `stopSession()` cleans up the entire session every time in `boringNotch/managers/WebcamManager.swift:299-312`.
- Several `@Published` properties manually call `objectWillChange.send()` in `didSet`, for example `previewLayer`, `isSessionRunning`, `authorizationStatus`, and `cameraAvailable` in `boringNotch/managers/WebcamManager.swift:13-36`.

Why this costs CPU:

- The webcam path is only expensive when used, but video capture is inherently high CPU/power.
- `.high` is likely unnecessary for a small notch mirror.
- Adding `AVCaptureVideoDataOutput` is unnecessary if the app only displays an `AVCaptureVideoPreviewLayer`.
- Manual `objectWillChange.send()` on `@Published` doubles notifications.

How to fix:

- Use `.low` or `.medium` preset for the notch preview.
- Remove `AVCaptureVideoDataOutput` unless frame processing is added later.
- Keep a configured session around after stop and tear it down after an idle timeout, rather than rebuilding immediately on each toggle.
- Remove manual `objectWillChange.send()` from `@Published` `didSet`.
- Defer camera availability checks until the mirror feature is visible or the user opens the mirror controls.

Expected result:

- Lower CPU when camera preview is active.
- Less setup/teardown cost.

### 13. Shelf persistence, thumbnails, and Quick Share have burst-cost issues

Evidence:

- `ShelfStateViewModel.items` writes the full shelf JSON file on every mutation in `boringNotch/components/Shelf/ViewModels/ShelfStateViewModel.swift:14-16`.
- Bookmark refreshes mutate `items`, which also writes persistence in `boringNotch/components/Shelf/ViewModels/ShelfStateViewModel.swift:51-77`.
- Each `ShelfItemViewModel` starts a thumbnail task in `init` in `boringNotch/components/Shelf/ViewModels/ShelfItemViewModel.swift:29-42`.
- `ThumbnailService` uses an unbounded in-memory dictionary cache and logs thumbnail work in `boringNotch/components/Shelf/Services/ThumbnailService.swift:13-84`.
- `ShelfItem.displayName`, `fileURL`, `icon`, and `identityKey` resolve security-scoped bookmarks and may read file contents in `boringNotch/components/Shelf/Models/ShelfItem.swift:54-146` and `boringNotch/components/Shelf/Models/ShelfItem.swift:190-204`.
- `QuickShareService.init()` discovers providers immediately, and `ShareServiceFinder` displays an invisible sharing picker with a 2-second timeout in `boringNotch/components/Shelf/Services/QuickShareService.swift:29-74` and `boringNotch/components/Shelf/Services/ShareServiceFinder.swift:15-46`.

Why this costs CPU:

- Shelf work is mostly bursty, but it can still affect idle if Quick Share starts at launch.
- Writing the full JSON file on every item mutation is O(number of shelf items).
- Bookmark resolution and icon lookup can be expensive if SwiftUI evaluates computed properties repeatedly.
- QuickLook thumbnail generation is relatively heavy and can run for every visible item.

How to fix:

- Debounce shelf persistence:
  - Use a `ShelfPersistenceActor`.
  - Save after 250-500 ms of inactivity or immediately on app termination.
  - Skip saves when encoded data is unchanged.
- Cache resolved shelf metadata in `ShelfItemViewModel`:
  - resolved URL
  - display name
  - icon
  - content type
  - is directory
- Avoid resolving bookmarks in computed properties that are called by SwiftUI body rendering.
- Add an `NSCache` or bounded LRU cache to `ThumbnailService`.
- Remove `NSLog` from thumbnail hot paths or gate it behind a debug flag.
- Limit concurrent thumbnail generation.
- Defer Quick Share discovery until:
  - the shelf tab first opens,
  - settings shelf section opens,
  - user invokes quick share.
- Cache provider discovery results with invalidation on app install/service changes if needed.

Expected result:

- Faster shelf interactions and lower burst CPU.
- Lower launch work.

### 14. Calendar and reminders can do unnecessary EventKit work

Evidence:

- `CalendarManager` reloads calendars on `.EKEventStoreChanged` in `boringNotch/managers/CalendarManager.swift:45-55`.
- `CalendarService.events()` calls `calendars()` each time, then repeatedly calls `store.calendars(for:)` while mapping and filtering in `boringNotch/Providers/CalendarServiceProviding.swift:57-82`.
- Reminder fetching loads reminders for selected lists and filters due dates in memory in `boringNotch/Providers/CalendarServiceProviding.swift:84-108`.

Why this costs CPU:

- EventKit can send broad change notifications.
- Calendar/reminder lists usually change rarely, so reloading them for each day view or event update is wasteful.
- Reminder lists can be large; fetching all reminders and filtering due date in memory is expensive for users with many reminders.

How to fix:

- Cache `EKCalendar` objects by identifier and invalidate only on `EKEventStoreChanged`.
- Debounce `.EKEventStoreChanged` by 500-1000 ms.
- In `events(from:to:calendars:)`, reuse cached calendar objects instead of repeatedly calling `store.calendars(for:)`.
- Fetch reminders with narrower predicates where possible:
  - incomplete reminders only when completed reminders are hidden,
  - selected reminder lists only,
  - cache reminder results for the selected day.
- Do not reload calendar/reminder lists on every authorization check if already loaded and not stale.

Expected result:

- Lower CPU when opening calendar or when EventKit posts broad changes.

### 15. Image processing is marked `@MainActor`

Evidence:

- `ImageProcessingService` is `@MainActor` in `boringNotch/components/Shelf/Services/ImageProcessingService.swift:34-39`.
- Background removal, image conversion, PDF creation, Core Image rendering, Vision, and PDFKit work are implemented on that actor in `boringNotch/components/Shelf/Services/ImageProcessingService.swift:44-276`.

Why this costs CPU:

- This is user-triggered burst work, not idle CPU.
- Marking the whole service `@MainActor` can keep CPU-heavy image operations on the main actor, hurting responsiveness and making app CPU feel worse.

How to fix:

- Remove `@MainActor` from the service.
- Keep only UI presentation and shelf insertion on main.
- Run Vision/Core Image/PDFKit work in a background task or actor.
- Reuse the existing `ciContext`; avoid creating new `CIContext()` inside `applyMask`, HEIC conversion, and scaling unless a different color-space context is required.
- For multi-image PDF creation, consider downscaling large source images or streaming pages to avoid memory spikes.

Expected result:

- Less main-thread contention during image actions.

## Lower-impact issues and correctness risks

### Logging in hot or semi-hot paths

Several paths log during normal operation:

- playback state changes in `MusicManager`
- thumbnail generation in `ThumbnailService`
- battery events in `BatteryStatusViewModel`
- media-key feedback sound path in `MediaKeyInterceptor`
- bookmark resolution/creation paths

Logging can become surprisingly expensive when repeated. Gate these behind a debug setting or use `os_log` with appropriate levels.

### `JSONLinesPipeHandler.readData()` repeatedly replaces `readabilityHandler`

`JSONLinesPipeHandler.processLines()` loops forever and each read installs a new `readabilityHandler` in `boringNotch/MediaControllers/NowPlayingController.swift:374-415`.

This works, but it is more complex and allocation-heavy than necessary. A simpler implementation can use:

- a single readability handler that appends data and drains complete lines, or
- `FileHandle.bytes.lines` if deployment target allows it, or
- a dedicated `PipeLineReader` actor with one long-lived handler.

### `PlaybackState.Equatable` ignores some fields but includes artwork

`PlaybackState.Equatable` ignores `lastUpdated`, `playbackRate`, and `volume`, but includes `artwork` in `boringNotch/models/PlaybackState.swift:33-46`.

For CPU, this is backwards:

- `lastUpdated` should usually not trigger UI diffing by itself.
- `volume` may need diffing in some UI paths.
- `artwork Data` is expensive and should not be compared directly.

Use a cheap media-state signature and publish position separately when necessary.

### Open-notch `TimelineView` refresh rates are interactive-only

`NotchHomeView` uses a 10 Hz `TimelineView` for the music slider and a 4 Hz `TimelineView` for lyrics in `boringNotch/components/Notch/NotchHomeView.swift:157-206`.

This does not run while the notch is closed because `NotchHomeView` is only built when `vm.notchState == .open` in `boringNotch/ContentView.swift:345-362`. It is still worth optimizing because the open notch can feel CPU-heavy during playback.

How to fix:

- Reduce the slider interval from 0.1 seconds to about 0.2 seconds.
- For synced lyrics, update only when the active lyric line index changes instead of polling at a fixed 4 Hz.
- Keep timeline-driven position estimation; it avoids requiring frequent MediaRemote elapsed-time updates.

### Hover and body recomputation do repeated settings/screen work

`ContentView` reads many `Defaults[...]` values inside computed properties and body branches, and `BoringViewModel.effectiveClosedNotchHeight` / `chinHeight` resolve screens by UUID in `boringNotch/models/BoringViewModel.swift:105-129`.

This is not a standalone backend loop, but it multiplies the cost of each media/fullscreen/HUD publish because SwiftUI re-evaluates these paths on invalidation.

How to fix:

- Mirror hot settings into `@Default` / `@AppStorage` / coordinator state once instead of direct `Defaults[...]` lookups throughout hot body paths.
- Cache the resolved `NSScreen` on the view model and invalidate it on screen-parameter changes.
- In hover handling, avoid recreating tasks for duplicate hover state and read `minimumHoverDuration` from cached state.

### Display and settings notification storms rebuild windows without coalescing

`AppDelegate` handles `NSApplication.didChangeScreenParametersNotification`, `NSWindow.didChangeScreenNotification`, selected-screen changes, notch-height changes, show-on-all-displays changes, and expanded-drag-detection changes in separate observers in `boringNotch/boringNotchApp.swift:255-335`.

Several handlers call combinations of `cleanupWindows()`, `adjustWindowPosition()`, and `setupDragDetectors()` immediately. During monitor attach/detach or rapid settings edits, this can rebuild windows and drag detectors repeatedly.

How to fix:

- Route all display/settings/layout invalidations through a single coalesced `scheduleWindowRebuild(reason:)`.
- Debounce by 50-300 ms depending on event type.
- Collapse duplicate work into one pass that updates windows, positions them, and then rebuilds drag detectors once.

## Suggested implementation order

### Phase 1: Measurement and quick wins

1. Add `os_signpost` around:
   - media controller update handling
   - artwork decode/fetch
   - average artwork color calculation
   - `MusicManager.updateFromPlaybackState`
   - closed-notch visualizer start/stop
   - fullscreen detector updates
   - drag detector callbacks
   - CoreAudio volume reads/writes
   - XPC brightness get/set
   - shelf persistence saves
2. Run Instruments Time Profiler in these scenarios:
   - idle, notch closed, no music playing
   - music playing, notch closed
   - repeatedly hover open/close
   - all displays enabled
   - expanded drag detection enabled while dragging in another app
   - HUD replacement enabled while holding volume/brightness keys
   - optional face enabled, repeatedly appearing/disappearing
3. Remove noisy logs from hot paths.
4. Add debounce to the MediaRemote adapter stream.
5. Pause closed-notch visualizers when the window is occluded, hidden, or in Low Power Mode.
6. Fix the unmanaged `AnimatedFace` timer.
7. Replace full-image average color calculation with a 1x1 downsample or `CIAreaAverage`.
8. Guard `FullscreenMediaDetector` assignment with equality.
9. Make `BoringViewModel.open()` force-update media only when stale.

### Phase 2: Media subsystem cleanup

1. Remove `Data` comparisons from media state.
2. Batch `MusicManager` published state.
3. Cache `ISO8601DateFormatter` and `JSONDecoder` on the hot stream path.
4. Debounce Apple Music and Spotify notification handling.
5. Split cheap player updates from expensive artwork/favorite/lyrics updates.
6. Add lyrics task cancellation and title/artist cache.
7. Improve YouTube Music polling, like-state fetch, and artwork URL caching.

### Phase 3: Lifecycle and feature gating

1. Make manager initializers cheap.
2. Add a backend `FeatureRuntimeCoordinator`.
3. Start/stop:
   - fullscreen detector based on `hideNotchOption`
   - media controller based on media feature visibility/activity
   - Quick Share discovery based on shelf/setting usage
   - webcam availability/session based on mirror usage
4. Replace per-screen `DragDetector` monitors with one shared manager.
5. Coalesce display/settings/window rebuild notifications.

### Phase 4: I/O and actor cleanup

1. Move shelf persistence to a debounce actor.
2. Cache shelf metadata instead of resolving bookmarks in computed properties.
3. Bound thumbnail cache and limit concurrency.
4. Move image processing off `@MainActor`.
5. Cache EventKit calendars/reminders and debounce store changes.
6. Cache hot screen/default-derived values that are currently recomputed during SwiftUI invalidation.

## Expected biggest wins

The most likely CPU reductions, in order:

1. MediaRemote stream debounce plus stale-aware force updates.
2. Pausing/removing continuous closed-notch visualizer work during playback.
3. Replacing full-resolution average-color scans and raw artwork `Data` comparisons.
4. Cheap singleton initialization plus backend lifecycle gating.
5. Batch publishing from `MusicManager`.
6. Fullscreen detector start/stop and equality guard.
7. One shared drag detector instead of per-screen global monitors.
8. CoreAudio/XPC brightness coalescing during key repeats.
9. Debounced shelf persistence and deferred Quick Share discovery.

## What is probably not the main idle CPU source

- Battery monitoring is event-driven through IOKit; it can be cleaned up, but it is unlikely to dominate idle CPU.
- Sparkle updater setup is unlikely to be the main issue.
- Webcam capture is expensive only when the mirror/camera preview is running.
- Image processing is expensive only when the user invokes image actions.
- AppleScript is not the default media path; it matters for users who choose the Apple Music or Spotify controllers.
- YouTube Music polling is not the default media path; it matters when that controller is selected and WebSocket is unavailable.
- Drag detection is not an idle loop; it matters during active drag operations, especially on multi-display setups.

## Backend-only constraint notes

Most fixes above can be implemented without changing visible frontend behavior. Some lifecycle fixes may require small call-site changes so the backend knows when a feature becomes visible or hidden. If frontend files must remain untouched, the backend-compatible alternative is to keep all existing `shared` references working but make constructors side-effect free, then start runtime services from `AppDelegate` or a new backend coordinator that observes defaults and app/window state.
