# Feature Handoff: Spotify Ad Dampener

## Original request

User asked to implement the planned Spotify Ad Dampener feature for the boring.notch repo. Prior product direction: full-product implementation, not MVP; use Spotify OAuth + Web API as source of truth; store tokens in Keychain only; lower whole Mac volume during Spotify ads; restore after ads; avoid dampening while the user is in a call; respect manual volume changes; include Settings UI and verification.

## Implementation summary

- Added a testable SwiftPM core package for Spotify playback parsing, PKCE, dampener state machine, and conservative call-guard rules.
- Integrated the core package into the Xcode app target.
- Added Spotify OAuth Authorization Code + PKCE flow with custom callback URL `boringnotch://spotify-auth/callback`.
- Added Keychain-backed token storage for Spotify access/refresh tokens. No client secret is used.
- Added Spotify Web API playback polling using `/v1/me/player/currently-playing` and the core parser.
- Added runtime monitoring, call guard, dampener manager, stale-session restore, and manual-volume release behavior.
- Added safe automation methods to `VolumeManager`.
- Added a Settings > Media card for the feature with connection/config/status states, target volume control, and manual call suppression.
- The feature is fail-closed if `SPOTIFY_CLIENT_ID` is not configured: Connect is disabled and settings show that the client ID is missing.

Known limitations / required human setup:
- Real Spotify OAuth requires a Spotify Developer app configured with redirect URI `boringnotch://spotify-auth/callback`.
- `SPOTIFY_CLIENT_ID` must be supplied through build settings / Info expansion or an environment-style config. No secret should be configured.
- Real ad/call behavior has not been manually verified with a live Spotify ad and an active call in this session.

## Changed files

- `SpotifyAdDampenerCore/Package.swift`: new local SwiftPM package.
- `SpotifyAdDampenerCore/Sources/SpotifyAdDampenerCore/SpotifyPlaybackModels.swift`: playback snapshot models.
- `SpotifyAdDampenerCore/Sources/SpotifyAdDampenerCore/SpotifyPlaybackParser.swift`: Web API parser.
- `SpotifyAdDampenerCore/Sources/SpotifyAdDampenerCore/PKCE.swift`: PKCE verifier/challenge/auth URL builder.
- `SpotifyAdDampenerCore/Sources/SpotifyAdDampenerCore/AdDampenerStateMachine.swift`: pure dampening state machine.
- `SpotifyAdDampenerCore/Sources/SpotifyAdDampenerCore/CallGuardRules.swift`: pure conservative call suppression rules.
- `SpotifyAdDampenerCore/Tests/SpotifyAdDampenerCoreTests/*.swift`: 19 tests covering parser, PKCE, state machine, and call guard rules.
- `boringNotch/Services/KeychainTokenStore.swift`: Keychain persistence.
- `boringNotch/Services/SpotifyAuthToken.swift`: token response/model.
- `boringNotch/Services/SpotifyAuthConfiguration.swift`: client ID/config/redirect/scope config.
- `boringNotch/Services/SpotifyAuthService.swift`: OAuth PKCE connection, callback, token exchange/refresh.
- `boringNotch/Services/SpotifyPlaybackAPI.swift`: currently-playing API wrapper.
- `boringNotch/Services/CallGuardService.swift`: conservative runtime call suppression signals.
- `boringNotch/Services/SpotifyAdMonitor.swift`: Spotify API monitor and notification-triggered refresh.
- `boringNotch/managers/SpotifyAdDampenerManager.swift`: runtime orchestration, volume commands, defaults persistence.
- `boringNotch/managers/VolumeManager.swift`: safe Spotify dampener volume automation methods.
- `boringNotch/models/Constants.swift`: Defaults keys.
- `boringNotch/components/Settings/SettingsView.swift`: settings card.
- `boringNotch/boringNotchApp.swift`: manager init, callback URL handling, termination restore.
- `boringNotch/Info.plist`: Spotify callback URL scheme and client ID info key.
- `boringNotch.xcodeproj/project.pbxproj`: local package dependency and new app source files.

## How to test

1. Core package:
   - `cd /Users/ziadnasreldin/Documents/GitHub/boring.notch/SpotifyAdDampenerCore && swift test`
   - Expected: 19 tests pass.
2. App build:
   - `cd /Users/ziadnasreldin/Documents/GitHub/boring.notch && xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO`
   - Expected: build succeeds.
3. Manual OAuth setup:
   - Configure a Spotify Developer app redirect URI: `boringnotch://spotify-auth/callback`.
   - Provide `SPOTIFY_CLIENT_ID` through the app build configuration / Info expansion.
   - Launch app, open Settings > Media, connect Spotify.
4. Manual feature check:
   - With Spotify connected and feature enabled, force/observe a Spotify ad.
   - Confirm system volume lowers to configured target, then restores after ad ends.
   - Start a call/call-like app or enable manual call suppression; confirm dampening does not start or restores immediately if already dampened.
   - Change system volume manually during dampening; confirm app releases ownership and does not restore over the user choice.

## Tests run

- `cd SpotifyAdDampenerCore && swift test`: PASS — 20 tests, 0 failures after target-volume live-update fix.
- `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO`: PASS — `** BUILD SUCCEEDED **`; existing warnings only.
- `git status --short`: PASS — working tree contains intended modified/untracked feature files plus `.hermes/` planning/review files.
- Lightweight secret string scan: no hardcoded Spotify client secret was found; Spotify API wrapper contains the expected runtime `Bearer` header construction only.

## Git info

- Branch: `main`
- Commit SHA: not committed
- Diff base: working tree against current `main`

## Frontend/backend/database notes

- Frontend/routes: macOS SwiftUI Settings > Media card only.
- Backend endpoints/services: none; Spotify Web API is called directly by the macOS app with OAuth token.
- Database: none.
- Persistence: Spotify tokens in Keychain; non-sensitive feature settings and owned-session metadata in Defaults.

## Reviewer focus areas

- Verify no token/client-secret persistence outside Keychain.
- Verify OAuth state/PKCE/callback handling is safe and no client secret is used.
- Verify network/auth errors restore volume and clear owned session.
- Verify manual volume change handling does not fight user changes.
- Verify call guard is conservative enough and does not falsely claim precise call detection.
- Verify local SwiftPM package integration is correct for the Xcode project.
- Verify Settings UI is truthful when client ID is missing.
- Verify no sensitive playback/listening history is stored.

## Fix cycle notes

Critique R1 fixed:
- Added `AdDampenerEvent.targetVolumeChanged(Float)` and mutable `targetVolume` to the core state machine.
- Added `testTargetVolumeChangeAffectsNextAdWithoutRelaunch`, proving slider/default updates affect the next ad without app relaunch.
- Added a Defaults publisher in `SpotifyAdDampenerManager` for `.spotifyAdDampenerTargetVolume` to update the live state machine.
- Re-ran core tests and app build successfully.
