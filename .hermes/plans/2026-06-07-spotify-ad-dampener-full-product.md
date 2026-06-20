# Spotify Ad Dampener Full Product Brainstore

> For Hermes: before implementation, use the writing-plans skill to expand this into bite-sized TDD tasks. Because this is a feature change, completion requires the feature-critique-workflow gate and an APPROVED review in `.hermes/reviews/spotify-ad-dampener/`.

Goal: detect Spotify ads reliably and temporarily lower the Mac system output volume until the ad ends, except when the user is in a call.

Architecture: implement a full Spotify-authenticated ad detector backed by Spotify Web API, with local Spotify notifications as a fast refresh signal. Add a call-presence guard and a volume suppression state machine that saves/restores the user's real system volume safely.

Current repo evidence:
- `boringNotch/MediaControllers/SpotifyController.swift` already observes `com.spotify.client.PlaybackStateChanged` and reads Spotify via AppleScript.
- `boringNotch/managers/VolumeManager.swift` already reads/writes system output volume using CoreAudio.
- `boringNotch/managers/MusicManager.swift` centralizes playback state and media-source selection.
- `boringNotch/components/Settings/SettingsView.swift` already has a Music settings area and uses `Defaults` keys from `boringNotch/models/Constants.swift`.

## Product decision

Build the full version, not a heuristic MVP.

Canonical behavior:
1. User enables Spotify Ad Dampener in Settings.
2. App requires Spotify account connection before the feature can run.
3. App uses Spotify Web API playback state as the source of truth for ad detection.
4. When Spotify reports an ad and Spotify is playing, the app lowers whole Mac output volume to the configured dampened volume.
5. When Spotify reports a normal track, pause, stop, auth failure, no active device, or unsupported state, the app restores the saved pre-ad system volume.
6. If a call is detected at any point, the app restores volume immediately and suppresses ad dampening until the call ends.
7. If the user manually changes volume during dampening, the app does not fight them. It either adopts the user's new target or exits dampening safely.
8. If Boring Notch quits or crashes after lowering volume, the next launch should attempt safe restoration if it owns an active dampening session.

## Spotify authentication

Use Authorization Code with PKCE; do not embed a client secret in the Mac app.

Required Spotify scopes:
- `user-read-playback-state`
- `user-read-currently-playing`

Potentially optional later:
- `user-modify-playback-state` is not needed for volume dampening because we change Mac volume, not Spotify device volume.

Auth UX:
- Settings > Music > Spotify Ad Dampener card.
- Button: Connect Spotify.
- Open browser to Spotify authorization URL.
- Use custom URL scheme callback, e.g. `boringnotch://spotify-auth/callback`.
- Store access token and refresh token in Keychain, not `Defaults`.
- Show connected account state and Disconnect button.

Auth implementation modules:
- Create `boringNotch/Services/SpotifyAuthService.swift`.
- Create `boringNotch/Services/SpotifyPlaybackAPI.swift`.
- Create `boringNotch/Services/KeychainTokenStore.swift` if no existing token store is present.
- Add callback handling in the app entry point / URL handler.

Needed setup outside code:
- Register a Spotify developer app.
- Add redirect URI matching the app callback.
- Add the Spotify client ID to app config/build settings. Public client ID is acceptable; never store a client secret.

## Ad detection

Primary signal:
- Spotify Web API currently-playing/playback response field `currently_playing_type == "ad"`.

Polling/refresh model:
- Subscribe to existing Spotify local playback notifications to trigger immediate API refresh.
- Also run a low-frequency poll while Spotify is active, e.g. every 3-5 seconds.
- During detected ad, poll more frequently, e.g. every 1-2 seconds, so restoration is quick.
- Back off when Spotify is closed or user disconnected.

State categories:
- `unknown`: no action; restore if currently dampened.
- `track`: restore if dampened.
- `ad`: dampen if not in call.
- `episode`: restore unless product later chooses to dampen podcast ads too.
- `notPlaying`: restore.
- `authExpired`: refresh token; if refresh fails, restore and show reconnect state.

## Volume state machine

Create `SpotifyAdDampenerManager` as the owner of all dampening behavior.

States:
- `disabled`
- `idle`
- `monitoring`
- `dampened(sessionID, savedVolume, targetVolume, startedAt)`
- `suppressedByCall`
- `authRequired`
- `errorRecoverable`

Rules:
- Only the manager may perform automatic dampening/restoration.
- Save the current `VolumeManager` volume before lowering.
- Default dampened volume: 0.05 or 5%.
- Never set to 0 by default; full mute should be a setting.
- Restore to saved volume only if the manager still owns the dampened session.
- If the current system volume differs from target by more than a small threshold because of user action, treat user override as intentional and stop enforcing.
- On app launch, if persisted `ownedDampeningSession` exists, attempt one safe restore and clear it.

Volume settings:
- Enable/disable Spotify Ad Dampener.
- Dampened volume percent.
- Restore volume after ad toggle; default true.
- Respect manual volume changes; default true.
- Show notch indicator; default true.

## Call guard

Full-product guard should combine multiple conservative signals.

Call-active should be true if:
1. A known call app is running and microphone usage is active/likely, OR
2. macOS audio input activity indicates live capture by a known communication app, OR
3. User manually toggles “I’m in a call / disable dampening temporarily”.

Known call apps initial list:
- FaceTime: `com.apple.FaceTime`
- Zoom: `us.zoom.xos`
- Microsoft Teams: current/new Teams bundle IDs need verification during implementation
- Discord: `com.hnc.Discord`
- Slack: `com.tinyspeck.slackmacgap`
- WhatsApp: `net.whatsapp.WhatsApp`
- Telegram: `ru.keepcoder.Telegram`
- Browsers for Meet: Safari, Chrome, Arc, Edge; browser alone is not enough without mic/capture signal.

Implementation options to investigate:
- Process/bundle detection via `NSWorkspace.shared.runningApplications`.
- macOS microphone/camera indicators and/or AVCapture authorization state are not enough alone; authorization does not mean active call.
- CoreAudio process tap / audio input process inspection may require private or newer APIs; prefer public APIs first.
- ScreenCaptureKit/Control Center indicators may be restricted; avoid brittle UI scraping unless there is no public alternative.
- Fallback: if known call app is frontmost/running and recent microphone permission exists, suppress. Better false negative than lowering during a real call.

Default safety rule:
- If call state is uncertain but suspicious, do not dampen.

## Settings/UI

Add a card under Music settings:

Title: Spotify Ad Dampener
Subtitle: Lowers Mac volume during Spotify ads, then restores it automatically. Pauses while you are in calls.

Controls:
- Toggle: Enable Spotify Ad Dampener
- Connection state: Connected as `<Spotify display name>` / Not connected
- Button: Connect Spotify / Reconnect / Disconnect
- Slider: Ad volume, 0-30%, default 5%
- Toggle: Restore previous volume after ad, default on
- Toggle: Disable while in calls, default on
- Button or disclosure: Manage call apps
- Toggle: Show notch indicator while dampened, default on
- Debug status row: Last Spotify state, call guard state, last action, visible only in debug/advanced

Notch indicator:
- Small temporary indicator when dampening starts: “Spotify ad volume lowered”.
- Avoid noisy notifications.
- No indicator while in a call unless user opens settings/debug.

## Privacy and safety

- Tokens in Keychain only.
- No Spotify listening history stored beyond transient current playback state.
- No ad history by default.
- Debug logs must redact access tokens, refresh tokens, auth codes, and account IDs if persisted.
- Feature should be opt-in.
- On auth failure, never keep lowering volume.
- On network failure during an active dampening session, restore volume after a short timeout rather than staying low indefinitely.

## Testing strategy

Unit-testable pieces:
- Spotify API response parsing: ad/track/episode/unknown.
- PKCE verifier/challenge generation.
- Token refresh flow with mocked network.
- State machine transitions.
- Manual volume override behavior.
- Call guard decision matrix.
- Restore-on-failure paths.

Integration/manual verification:
- Connect Spotify account.
- Play normal track: volume unchanged.
- Trigger ad on free Spotify account: volume lowers.
- Ad ends: volume restores.
- Start call/simulated call guard: dampening suppressed.
- Start call during ad: volume restores immediately.
- Change volume manually during dampened ad: app does not fight user.
- Disconnect Spotify: feature stops safely.
- Quit/relaunch while dampened: safe restoration happens.

## Open implementation risks

1. Spotify Web API may report ads only for active playback under certain account/device conditions; verify with a free account and real ad.
2. OAuth redirect handling must fit existing macOS app entitlements and bundle setup.
3. Reliable active-call detection on macOS may require a conservative approximation if public APIs do not expose per-process mic activity.
4. System volume writes can behave differently across output devices; preserve existing `VolumeManager` fallback behavior.

## Build order

1. Create Spotify auth/token storage foundation.
2. Add Spotify API playback client and parsers.
3. Add Spotify ad monitor service using API + local playback notifications.
4. Add call guard service with conservative known-app detection and extension points.
5. Add volume dampening state machine.
6. Wire settings and defaults.
7. Add notch indicator/status feedback.
8. Add tests for parsing/state/call/volume logic.
9. Build and run locally.
10. Verify with Spotify real playback, real or simulated ad state, and simulated call guard.
11. Run feature critique workflow and fix Required items until APPROVED.
