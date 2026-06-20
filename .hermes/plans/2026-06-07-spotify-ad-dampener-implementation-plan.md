# Spotify Ad Dampener Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task. Use strict TDD for all pure logic. Because this changes product behavior, completion requires feature-critique-workflow: create `.hermes/reviews/spotify-ad-dampener/handoff.md`, run/await critique, fix every Required item, and re-review until `Verdict: APPROVED`.

**Goal:** Add a full Spotify-authenticated feature that lowers the Mac system volume during Spotify ads and restores it when ads finish, while never dampening during calls.

**Architecture:** Keep Spotify ad detection reliable by using Spotify OAuth PKCE + Spotify Web API as the source of truth. Put testable parsing/state-machine/auth logic in a pure Swift module/package, then wire it into the macOS app through app services, Keychain token storage, Settings UI, URL callback handling, and the existing `VolumeManager` CoreAudio implementation.

**Tech Stack:** Swift, SwiftUI, Combine, AppKit, CoreAudio, Keychain Services, URLSession, Spotify Web API, XCTest/SwiftPM tests, existing Defaults package.

---

## Current code anchors

- `boringNotch/MediaControllers/SpotifyController.swift`
  - Already observes `com.spotify.client.PlaybackStateChanged` and reads local Spotify state through AppleScript.
- `boringNotch/managers/VolumeManager.swift`
  - Already reads/writes whole Mac output volume with CoreAudio.
- `boringNotch/managers/MusicManager.swift`
  - Centralizes playback state and media controller selection.
- `boringNotch/components/Settings/SettingsView.swift`
  - `struct Media` is the right place for the settings card.
- `boringNotch/models/Constants.swift`
  - Existing Defaults keys live here.
- Project currently has no test target listed by `xcodebuild -list`; add a testable SwiftPM core first so TDD is practical.

## Product rules

1. Feature is opt-in.
2. Enabling requires Spotify connection.
3. Spotify Web API is the source of truth for `ad` vs `track`.
4. On ad start, save current Mac output volume and lower system volume to configured dampened volume.
5. On ad end, pause, unknown state, auth failure, network timeout, Spotify closed, or no active playback, restore volume if the manager owns a dampened session.
6. If call guard says user is in/likely in a call, never start dampening.
7. If call starts during dampening, restore immediately and suppress until call ends.
8. If user manually changes volume during dampening, do not fight them.
9. Tokens must live in Keychain, not Defaults.
10. Do not persist listening/ad history by default.

## External prerequisite

Create a Spotify developer app before final real-world verification:

- Redirect URI: `boringnotch://spotify-auth/callback`
- Scopes:
  - `user-read-playback-state`
  - `user-read-currently-playing`
- Public Client ID must be provided to the app.
- No client secret is used or stored.

Implementation default:
- Add an Info.plist/build-setting key `SPOTIFY_CLIENT_ID`.
- If missing, Settings shows “Spotify Client ID missing” and Connect is disabled.

---

# Build Order

## Task 1: Create pure Swift core package for testable logic

**Objective:** Add a local SwiftPM package for parsing, PKCE, state machine, and call-guard rules without depending on AppKit/CoreAudio.

**Create:**
- `SpotifyAdDampenerCore/Package.swift`
- `SpotifyAdDampenerCore/Sources/SpotifyAdDampenerCore/SpotifyPlaybackModels.swift`
- `SpotifyAdDampenerCore/Sources/SpotifyAdDampenerCore/SpotifyPlaybackParser.swift`
- `SpotifyAdDampenerCore/Sources/SpotifyAdDampenerCore/PKCE.swift`
- `SpotifyAdDampenerCore/Sources/SpotifyAdDampenerCore/AdDampenerStateMachine.swift`
- `SpotifyAdDampenerCore/Sources/SpotifyAdDampenerCore/CallGuardRules.swift`
- `SpotifyAdDampenerCore/Tests/SpotifyAdDampenerCoreTests/SpotifyPlaybackParserTests.swift`
- `SpotifyAdDampenerCore/Tests/SpotifyAdDampenerCoreTests/PKCETests.swift`
- `SpotifyAdDampenerCore/Tests/SpotifyAdDampenerCoreTests/AdDampenerStateMachineTests.swift`
- `SpotifyAdDampenerCore/Tests/SpotifyAdDampenerCoreTests/CallGuardRulesTests.swift`

**Step 1: Write failing parser tests**

Test cases:
- `currently_playing_type: "ad"` parses as `.ad`.
- `currently_playing_type: "track"` parses as `.track`.
- `currently_playing_type: "episode"` parses as `.episode`.
- missing/unknown type parses as `.unknown`.
- HTTP 204/no body parses as `.notPlaying`.

Run:
`cd SpotifyAdDampenerCore && swift test --filter SpotifyPlaybackParserTests`

Expected: FAIL because parser does not exist.

**Step 2: Implement minimal parser**

`SpotifyPlaybackParser` should decode only fields needed now:

```swift
public enum SpotifyPlaybackKind: Equatable {
    case ad
    case track
    case episode
    case notPlaying
    case unknown(String?)
}

public struct SpotifyPlaybackSnapshot: Equatable {
    public let kind: SpotifyPlaybackKind
    public let isPlaying: Bool
    public let progressMs: Int?
    public let durationMs: Int?
}
```

**Step 3: Run parser tests**

Run:
`cd SpotifyAdDampenerCore && swift test --filter SpotifyPlaybackParserTests`

Expected: PASS.

**Step 4: Commit**

```bash
git add SpotifyAdDampenerCore
git commit -m "test: add Spotify playback parsing core"
```

## Task 2: Implement PKCE generation and auth URL building

**Objective:** Generate Spotify PKCE verifier/challenge and deterministic authorization URLs.

**Modify:**
- `SpotifyAdDampenerCore/Sources/SpotifyAdDampenerCore/PKCE.swift`
- `SpotifyAdDampenerCore/Tests/SpotifyAdDampenerCoreTests/PKCETests.swift`

**Step 1: Write failing PKCE tests**

Test cases:
- verifier length is 43-128 chars.
- verifier uses URL-safe chars.
- SHA256 challenge for known verifier matches expected RFC-style base64url output.
- auth URL contains `response_type=code`, client ID, redirect URI, scopes, `code_challenge_method=S256`, state, challenge.

Run:
`cd SpotifyAdDampenerCore && swift test --filter PKCETests`

Expected: FAIL.

**Step 2: Implement PKCE**

Use CryptoKit SHA256 and base64url without padding.

Public API:

```swift
public struct PKCEPair: Equatable {
    public let verifier: String
    public let challenge: String
}

public enum PKCE {
    public static func generateVerifier(byteCount: Int = 64) throws -> String
    public static func challenge(for verifier: String) -> String
}
```

**Step 3: Run tests**

Run:
`cd SpotifyAdDampenerCore && swift test --filter PKCETests`

Expected: PASS.

**Step 4: Commit**

```bash
git add SpotifyAdDampenerCore
git commit -m "feat: add Spotify PKCE helpers"
```

## Task 3: Build dampening state machine in pure Swift

**Objective:** Encode all volume/ad/call/user-override behavior in a testable state machine.

**Modify:**
- `SpotifyAdDampenerCore/Sources/SpotifyAdDampenerCore/AdDampenerStateMachine.swift`
- `SpotifyAdDampenerCore/Tests/SpotifyAdDampenerCoreTests/AdDampenerStateMachineTests.swift`

**Step 1: Write failing state machine tests**

Test cases:
- idle + ad + not in call => emits `.lowerVolume(savedVolume, targetVolume)` and enters dampened state.
- dampened + track => emits `.restoreVolume(savedVolume)` and returns idle.
- dampened + notPlaying => restores.
- idle + ad + call active => no lower, enters suppressed state.
- dampened + call active => restores immediately.
- dampened + network/auth error => restores.
- dampened + manual volume override => stops enforcing and does not restore over user choice.
- app launch with persisted owned session => emits one safe restore and clears session.

Run:
`cd SpotifyAdDampenerCore && swift test --filter AdDampenerStateMachineTests`

Expected: FAIL.

**Step 2: Implement minimal state machine**

Suggested public API:

```swift
public enum AdDampenerState: Equatable {
    case disabled
    case idle
    case monitoring
    case dampened(DampeningSession)
    case suppressedByCall
    case authRequired
    case errorRecoverable(String)
}

public struct DampeningSession: Equatable {
    public let id: UUID
    public let savedVolume: Float
    public let targetVolume: Float
    public let startedAt: Date
}

public enum AdDampenerEvent: Equatable {
    case settingsEnabled(Bool)
    case spotifyPlayback(SpotifyPlaybackSnapshot)
    case callActive(Bool)
    case currentSystemVolume(Float)
    case manualVolumeChanged(Float)
    case authFailed
    case networkFailed
    case appLaunchedWithOwnedSession(DampeningSession)
}

public enum AdDampenerCommand: Equatable {
    case lowerVolume(to: Float, save: Float, sessionID: UUID)
    case restoreVolume(to: Float, sessionID: UUID)
    case persistOwnedSession(DampeningSession)
    case clearOwnedSession
    case showIndicator(String)
    case none
}
```

**Step 3: Run focused and full core tests**

Run:
`cd SpotifyAdDampenerCore && swift test`

Expected: PASS.

**Step 4: Commit**

```bash
git add SpotifyAdDampenerCore
git commit -m "feat: add Spotify ad dampener state machine"
```

## Task 4: Build call guard rules in pure Swift

**Objective:** Decide when dampening should be suppressed from app/mic/capture signals.

**Modify:**
- `SpotifyAdDampenerCore/Sources/SpotifyAdDampenerCore/CallGuardRules.swift`
- `SpotifyAdDampenerCore/Tests/SpotifyAdDampenerCoreTests/CallGuardRulesTests.swift`

**Step 1: Write failing tests**

Test cases:
- Zoom running + microphone active => call active.
- FaceTime running + microphone active => call active.
- Discord running + microphone active => call active.
- Browser running without microphone/capture signal => not enough.
- Microphone active with unknown app => suspicious, suppress by default.
- No microphone/capture + known app idle => not active.
- Manual “suppress dampening” override => call active.

Run:
`cd SpotifyAdDampenerCore && swift test --filter CallGuardRulesTests`

Expected: FAIL.

**Step 2: Implement rules**

Expose known bundle IDs as data, not hard-coded branches, so settings can override later.

Initial known bundle IDs:
- `com.apple.FaceTime`
- `us.zoom.xos`
- `com.microsoft.teams2`
- `com.microsoft.teams`
- `com.hnc.Discord`
- `com.tinyspeck.slackmacgap`
- `net.whatsapp.WhatsApp`
- `ru.keepcoder.Telegram`
- browsers: `com.apple.Safari`, `com.google.Chrome`, `company.thebrowser.Browser`, `com.microsoft.edgemac`

**Step 3: Run tests**

Run:
`cd SpotifyAdDampenerCore && swift test`

Expected: PASS.

**Step 4: Commit**

```bash
git add SpotifyAdDampenerCore
git commit -m "feat: add conservative call guard rules"
```

## Task 5: Integrate local core package into Xcode project

**Objective:** Make app target import `SpotifyAdDampenerCore`.

**Modify:**
- `boringNotch.xcodeproj/project.pbxproj`

**Step 1: Add the local package**

Add `SpotifyAdDampenerCore` as a local Swift package dependency to the `boringNotch` target.

Implementation options:
- Use Xcode UI: File > Add Package Dependencies > Add Local... > `SpotifyAdDampenerCore`.
- Or edit `project.pbxproj` carefully to add the local package reference and product dependency.

**Step 2: Verify build sees the package**

Create a temporary import in a scratch build-only file or in the later service file.

Run:
`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Expected: Build reaches Swift compilation. If signing/helper embedding blocks CLI build, capture exact blocker and use the closest available `xcodebuild build` command that works locally.

**Step 3: Commit**

```bash
git add boringNotch.xcodeproj/project.pbxproj SpotifyAdDampenerCore
git commit -m "build: add Spotify ad dampener core package"
```

## Task 6: Add secure token storage

**Objective:** Store Spotify tokens in Keychain and expose a small async token store API.

**Create:**
- `boringNotch/Services/KeychainTokenStore.swift`
- `boringNotch/Services/SpotifyAuthToken.swift`

**Step 1: Write unit tests if app test target exists; otherwise add core contract tests first**

If an app XCTest target has been added, create:
- `boringNotchTests/KeychainTokenStoreTests.swift`

Test cases:
- save/load/delete token round trip.
- overwriting token replaces old value.
- token values are not stored in Defaults.

If app test target is not ready, add an implementation checklist and verify with a local debug-only manual command after build.

**Step 2: Implement KeychainTokenStore**

Use Security framework APIs:
- `SecItemAdd`
- `SecItemCopyMatching`
- `SecItemUpdate`
- `SecItemDelete`

Store under service name like `theboringteam.boringnotch.spotify`.

Token model:

```swift
struct SpotifyAuthToken: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let tokenType: String
    let scope: String
}
```

**Step 3: Verify**

Run:
`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

**Step 4: Commit**

```bash
git add boringNotch/Services/KeychainTokenStore.swift boringNotch/Services/SpotifyAuthToken.swift
git commit -m "feat: store Spotify OAuth tokens in Keychain"
```

## Task 7: Add Spotify auth service

**Objective:** Support OAuth PKCE start, callback handling, token exchange, refresh, disconnect.

**Create:**
- `boringNotch/Services/SpotifyAuthService.swift`
- `boringNotch/Services/SpotifyAuthConfiguration.swift`

**Modify:**
- `boringNotch/boringNotchApp.swift`
- app Info.plist / project URL types for `boringnotch://spotify-auth/callback`
- project build settings for `SPOTIFY_CLIENT_ID`

**Step 1: Write tests around URL generation in core or app service**

Test cases:
- auth URL includes correct redirect URI and scopes.
- callback with wrong state is rejected.
- callback with error returns a safe error state.

Run applicable test:
`cd SpotifyAdDampenerCore && swift test --filter PKCETests`

Expected: FAIL until auth URL builder exists.

**Step 2: Implement SpotifyAuthConfiguration**

Read client ID from Info.plist/build settings. Do not hardcode a secret.

**Step 3: Implement SpotifyAuthService**

Responsibilities:
- `startAuthorization()` opens browser with PKCE URL.
- `handleCallback(url:)` validates state and exchanges code for tokens.
- `validAccessToken()` refreshes if expired.
- `disconnect()` clears Keychain.
- Publish auth state for Settings UI.

**Step 4: Wire URL callback**

In `boringNotchApp.swift`, add `.onOpenURL` or equivalent app-level URL handler and route Spotify callback to `SpotifyAuthService.shared.handleCallback(url:)`.

**Step 5: Verify build**

Run:
`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

**Step 6: Commit**

```bash
git add boringNotch/Services/SpotifyAuthService.swift boringNotch/Services/SpotifyAuthConfiguration.swift boringNotch/boringNotchApp.swift boringNotch.xcodeproj/project.pbxproj
git commit -m "feat: add Spotify OAuth PKCE flow"
```

## Task 8: Add Spotify playback API client

**Objective:** Fetch current playback and parse `currently_playing_type` reliably.

**Create:**
- `boringNotch/Services/SpotifyPlaybackAPI.swift`

**Step 1: Write tests using mocked URLProtocol if app tests exist**

Test cases:
- 200 ad JSON => `.ad`.
- 200 track JSON => `.track`.
- 204 => `.notPlaying`.
- 401 triggers auth refresh path or auth-required result.
- malformed JSON => `.unknown` / recoverable error.

If app tests are not available, keep parsing tests in core and manually test URLSession through a temporary injected protocol after app test target is added.

**Step 2: Implement SpotifyPlaybackAPI**

Endpoint:
- `GET https://api.spotify.com/v1/me/player/currently-playing`

Headers:
- `Authorization: Bearer <access_token>`

Return `SpotifyPlaybackSnapshot` from core.

**Step 3: Verify**

Run:
`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

**Step 4: Commit**

```bash
git add boringNotch/Services/SpotifyPlaybackAPI.swift
git commit -m "feat: add Spotify playback API client"
```

## Task 9: Add CallGuardService app adapter

**Objective:** Convert macOS app/process/mic signals into core call-guard inputs.

**Create:**
- `boringNotch/Services/CallGuardService.swift`

**Step 1: Write app-level tests if possible**

Test the mapping from running bundle IDs + mic signal bool + manual suppress flag into `CallGuardRules`.

**Step 2: Implement service**

Public API:

```swift
final class CallGuardService: ObservableObject {
    static let shared = CallGuardService()
    @Published private(set) var isCallLikelyActive: Bool = false
    func refresh()
}
```

Implementation notes:
- Use `NSWorkspace.shared.runningApplications` for bundle IDs.
- Add a small adapter method for microphone/capture state. Use public APIs only.
- If reliable active mic ownership is unavailable on this macOS target, implement conservative fallback:
  - known call app running + user enabled call guard + optional manual suppression => suppress;
  - browser-only without mic/capture signal is not enough;
  - suspicious unknown active mic => suppress.
- Keep rules in core; app service only gathers signals.

**Step 3: Verify build**

Run:
`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

**Step 4: Commit**

```bash
git add boringNotch/Services/CallGuardService.swift
git commit -m "feat: add conservative call guard service"
```

## Task 10: Add Spotify ad monitor

**Objective:** Poll Spotify Web API, refresh immediately on local Spotify playback notifications, and publish playback kind.

**Create:**
- `boringNotch/Services/SpotifyAdMonitor.swift`

**Step 1: Write tests for monitor scheduling if app tests exist**

Test with mocked clock/API:
- idle poll interval is 3-5s.
- ad interval is 1-2s.
- local Spotify notification triggers immediate refresh.
- disconnected auth stops polling.

**Step 2: Implement monitor**

Responsibilities:
- Start only when feature enabled and auth connected.
- Subscribe to `com.spotify.client.PlaybackStateChanged` via `DistributedNotificationCenter`.
- Poll current playback via `SpotifyPlaybackAPI`.
- Publish latest `SpotifyPlaybackSnapshot` and error/auth state.
- Back off when Spotify app is closed.

**Step 3: Verify build**

Run:
`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

**Step 4: Commit**

```bash
git add boringNotch/Services/SpotifyAdMonitor.swift
git commit -m "feat: monitor Spotify ads through Web API"
```

## Task 11: Add volume adapter methods to VolumeManager

**Objective:** Let dampener read current volume and set absolute volume without showing normal HUD spam unless desired.

**Modify:**
- `boringNotch/managers/VolumeManager.swift`

**Step 1: Write state-machine tests first**

Before touching `VolumeManager`, ensure Task 3 state machine tests cover save/restore/manual override rules.

Run:
`cd SpotifyAdDampenerCore && swift test --filter AdDampenerStateMachineTests`

Expected: PASS before adapter wiring.

**Step 2: Add public read/apply API**

Add safe methods:

```swift
func currentOutputVolume() -> Float32?
@MainActor func setOutputVolumeForAutomation(_ value: Float32, showHUD: Bool)
```

Rules:
- Clamp 0...1.
- Do not toggle mute unless target is exactly 0.
- Allow caller to suppress HUD.
- Publish volume after write.

**Step 3: Verify existing behavior still builds**

Run:
`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

**Step 4: Commit**

```bash
git add boringNotch/managers/VolumeManager.swift
git commit -m "feat: expose safe automated volume control"
```

## Task 12: Add SpotifyAdDampenerManager integration

**Objective:** Wire monitor + call guard + state machine + VolumeManager into the real feature.

**Create:**
- `boringNotch/managers/SpotifyAdDampenerManager.swift`

**Modify:**
- `boringNotch/boringNotchApp.swift` or app startup owner to initialize manager.

**Step 1: Write integration tests if app test target exists**

Use fake monitor/call guard/volume adapter:
- ad lowers volume.
- track restores.
- call active restores.
- manual volume change stops enforcement.
- auth failure restores.

**Step 2: Implement manager**

Responsibilities:
- Observe Defaults/settings.
- Start/stop monitor.
- Feed Spotify snapshots and call-guard state into core state machine.
- Execute commands against `VolumeManager`.
- Persist owned dampening session minimally in Defaults or app support, without storing listening history.
- On launch, clear/restore owned session.

**Step 3: Add Defaults keys**

Modify `boringNotch/models/Constants.swift`:

```swift
static let spotifyAdDampenerEnabled = Key<Bool>("spotifyAdDampenerEnabled", default: false)
static let spotifyAdDampenerVolume = Key<Double>("spotifyAdDampenerVolume", default: 0.05)
static let spotifyAdDampenerRestoreAfterAd = Key<Bool>("spotifyAdDampenerRestoreAfterAd", default: true)
static let spotifyAdDampenerDisableDuringCalls = Key<Bool>("spotifyAdDampenerDisableDuringCalls", default: true)
static let spotifyAdDampenerShowIndicator = Key<Bool>("spotifyAdDampenerShowIndicator", default: true)
static let spotifyAdDampenerManualSuppress = Key<Bool>("spotifyAdDampenerManualSuppress", default: false)
```

If persisting owned session in Defaults, store only session id/saved volume/target volume/timestamp. No track/ad metadata.

**Step 4: Verify**

Run:
`cd SpotifyAdDampenerCore && swift test`

Run:
`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

**Step 5: Commit**

```bash
git add boringNotch/managers/SpotifyAdDampenerManager.swift boringNotch/models/Constants.swift boringNotch/boringNotchApp.swift
git commit -m "feat: wire Spotify ad dampening manager"
```

## Task 13: Add Settings UI card

**Objective:** Let user connect Spotify, enable feature, configure volume, and see truthful state.

**Modify:**
- `boringNotch/components/Settings/SettingsView.swift`

**Create optionally:**
- `boringNotch/components/Settings/SpotifyAdDampenerSettingsView.swift`

**Step 1: Write UI-adjacent tests if available**

At minimum, test view model states if a separate view model is created:
- missing client ID disables connect button.
- disconnected shows Connect Spotify.
- connected shows Connected and Disconnect.
- auth error shows Reconnect.
- call guard active shows “Paused during call”.

**Step 2: Implement settings card**

Add under `struct Media` after Media Source or before Live Activity:

Controls:
- Toggle: `Spotify Ad Dampener`
- Status: Not connected / Connected / Reconnect required / Missing Client ID
- Button: Connect Spotify / Reconnect / Disconnect
- Slider: `Ad volume` from 0...0.30, default 0.05
- Toggle: Restore previous volume after ad
- Toggle: Disable while in calls
- Toggle: Show notch indicator
- Toggle: Temporarily suppress dampening, for manual call override
- Debug disclosure: current playback kind, call guard state, last action

Truthfulness:
- If not connected, enabling toggle should either stay off or show Connect requirement.
- Do not claim Spotify is connected until token exists and `/me` or playback request succeeds.

**Step 3: Verify build**

Run:
`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

**Step 4: Commit**

```bash
git add boringNotch/components/Settings/SettingsView.swift boringNotch/components/Settings/SpotifyAdDampenerSettingsView.swift
git commit -m "feat: add Spotify ad dampener settings"
```

## Task 14: Add notch indicator feedback

**Objective:** Show a subtle status when automatic dampening starts/restores without noisy notifications.

**Modify likely:**
- `boringNotch/BoringViewCoordinator.swift`
- `boringNotch/enums/generic.swift` if indicator type enum needs extension
- relevant live activity/HUD components if needed

**Step 1: Write source-level/view-model test if available**

Test that manager emits indicator command only when `showIndicator` is true.

**Step 2: Implement indicator**

Preferred minimal UI:
- Use existing sneak peek/HUD system if possible.
- Text: `Spotify ad volume lowered` on dampen.
- Text: `Volume restored` only if not noisy; otherwise skip restore message.
- Do not display during call suppression unless user opens settings/debug.

**Step 3: Verify build**

Run:
`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

**Step 4: Commit**

```bash
git add boringNotch/BoringViewCoordinator.swift boringNotch/enums/generic.swift boringNotch/components
git commit -m "feat: show Spotify ad dampener indicator"
```

## Task 15: Add app-level XCTest target if not already done

**Objective:** Cover app service adapters that cannot live in the pure Swift package.

**Modify:**
- `boringNotch.xcodeproj/project.pbxproj`

**Create:**
- `boringNotchTests/SpotifyAuthServiceTests.swift`
- `boringNotchTests/SpotifyPlaybackAPITests.swift`
- `boringNotchTests/SpotifyAdDampenerManagerTests.swift`
- `boringNotchTests/CallGuardServiceTests.swift`

**Step 1: Add XCTest target**

Add macOS Unit Testing Bundle target named `boringNotchTests`, host app `boringNotch` if needed.

**Step 2: Move adapter tests from TODO/skipped to real XCTest**

Tests should use injected fake dependencies, not real Spotify/network/volume.

**Step 3: Run tests**

Run:
`xcodebuild test -project boringNotch.xcodeproj -scheme boringNotch -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

Expected: PASS or clear signing-related blocker. If signing blocks tests, run the SwiftPM core tests plus `xcodebuild build` and record the blocker in handoff.

**Step 4: Commit**

```bash
git add boringNotch.xcodeproj/project.pbxproj boringNotchTests
git commit -m "test: add app tests for Spotify ad dampener"
```

## Task 16: Real local auth and playback verification

**Objective:** Prove the full Spotify OAuth + playback path works locally.

**Prerequisite:** User or implementer provides Spotify Client ID from developer dashboard.

**Step 1: Configure Client ID**

Add Client ID through build setting/config, not committed secret:
- public client ID may be committed if desired, but prefer local xcconfig ignored from git if this is personal.
- no client secret.

**Step 2: Run app from Xcode or CLI**

Run:
`xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`

Then launch built app or run from Xcode.

**Step 3: Verify OAuth**

Manual expected results:
- Settings shows Connect Spotify.
- Click Connect Spotify opens Spotify auth page.
- Callback returns to app.
- Settings shows connected state.
- Keychain contains token item.
- Defaults does not contain raw token.

**Step 4: Verify normal track**

Expected:
- Spotify normal track playing.
- Playback API reports `track`.
- System volume remains unchanged.

**Step 5: Verify ad**

Use a free Spotify account or known ad trigger.

Expected:
- Playback API reports `ad`.
- System output volume lowers to configured percentage.
- Indicator shows if enabled.
- When ad ends and track resumes, volume restores.

**Step 6: Verify call guard**

Manual/simulated expected results:
- Enable manual suppress toggle: ad does not lower volume.
- Turn suppress on during dampened ad: volume restores.
- With known call app + mic/call signal, dampening is suppressed.

**Step 7: Verify manual volume override**

Expected:
- During dampened ad, user changes volume manually.
- App does not reset it back to target repeatedly.
- Ad end does not overwrite user's intentional new choice unless state-machine rule says restore is still safe.

## Task 17: Final local verification gates

**Objective:** Run all realistic automated checks before critique.

Run:

```bash
cd /Users/ziadnasreldin/Documents/GitHub/boring.notch
cd SpotifyAdDampenerCore && swift test
cd ..
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

If app XCTest target exists:

```bash
xcodebuild test -project boringNotch.xcodeproj -scheme boringNotch -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Also run:

```bash
git diff --check
git status --short
```

Expected:
- Core tests pass.
- App builds.
- App tests pass or exact signing/test-target blocker is documented.
- No whitespace errors.
- Intended source/test/review files are tracked.

## Task 18: Feature critique handoff and approval loop

**Objective:** Complete the required review gate.

**Create:**
- `.hermes/reviews/spotify-ad-dampener/handoff.md`

Handoff must include:
- Original request: “detect whenever I get an ad in Spotify and automatically lower my whole Mac mini volume until ads finish, only when not in a call; full product with auth.”
- Implementation summary.
- Changed files.
- Commands run and actual results.
- Spotify Client ID/auth setup notes.
- Manual verification notes for OAuth, track, ad, call guard, manual volume override.
- Known limitations around public macOS call detection APIs.
- Reviewer focus: token safety, volume restore safety, call suppression, false-positive ad detection, no listening history persistence.

Then trigger/wait for critique report:
- `.hermes/reviews/spotify-ad-dampener/critique-report.md`

If `REQUEST_CHANGES`:
1. Fix every Required item.
2. Re-run focused tests/build.
3. Update handoff with fix cycle notes.
4. Re-review until `APPROVED`.

Only after `APPROVED` can this feature be called complete.

---

# Acceptance checklist

- [ ] Spotify Connect works through OAuth PKCE.
- [ ] Tokens are in Keychain, not Defaults.
- [ ] Missing Client ID disables connect with truthful copy.
- [ ] Spotify playback API parses `ad`, `track`, `episode`, `notPlaying`, `unknown`.
- [ ] Ad lowers whole Mac output volume to configured percent.
- [ ] Track/not playing/auth/network failures restore safely.
- [ ] Call guard suppresses dampening.
- [ ] Call starting during ad restores immediately.
- [ ] Manual volume changes are respected.
- [ ] Quit/relaunch after owned dampening session attempts safe restore and clears stale session.
- [ ] Settings UI exposes enable/connect/volume/restore/call/indicator controls.
- [ ] No listening/ad history persisted by default.
- [ ] Core Swift tests pass.
- [ ] App builds through xcodebuild.
- [ ] App tests pass if target added; otherwise blocker documented.
- [ ] Real Spotify OAuth/playback verified with a real account.
- [ ] Feature critique verdict is APPROVED.

# Important implementation notes

- Do not use Spotify AppleScript heuristics as the primary ad detector. AppleScript/local notifications are only refresh triggers.
- Do not embed Spotify client secret.
- Do not lower volume if call state is uncertain but suspicious.
- Restore volume quickly on any failure while dampened.
- Keep volume writes owned by a session ID so stale async callbacks cannot restore/lower incorrectly.
- Keep all debug logs token-redacted.
- Prefer false negatives over false positives for calls: missing one muted ad is acceptable; lowering volume during a call is not.
