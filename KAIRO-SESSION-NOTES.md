# Kairo Notch — Development Session Notes

**Last updated:** 2026-04-09
**Project path:** `/Users/wizlox/Developer/kairo-notch/`
**Xcode project:** `Kairo.xcodeproj`
**Bundle ID:** `com.kairo.app`
**Build output:** `/Users/wizlox/Library/Developer/Xcode/DerivedData/Kairo-aolbbfiolspucjfcmvytwhkdbwsf/Build/Products/Debug/Kairo.app`

---

## What Is Kairo Notch

A macOS Dynamic Island app — an AI-powered personal assistant that lives in the notch area of the screen. Originally forked from the open-source **boringNotch** project (by TheBoredTeam), but fully rebranded and extended with intelligent features: voice commands, smart home control, AI chat, web search, music control, notifications, and more.

The goal: **Jarvis-like personal assistant** that sees everything, speaks naturally, controls your Mac and smart home, all from a premium notch UI.

---

## What Was Done (Complete History)

### Phase 1: Full Rebrand (boringNotch -> Kairo)

Every trace of "boring" was removed from the entire codebase:

- **Type renames** across 27+ files:
  - `BoringViewModel` -> `KairoViewModel`
  - `BoringViewCoordinator` -> `KairoViewCoordinator`
  - `BoringAnimations` -> `KairoAnimations`
  - `BoringNotchSkyLightWindow` -> `KairoSkyLightWindow`
  - `BoringNotchWindow` -> `KairoNotchWindow`
  - `BoringHeader` -> `KairoHeader`
  - `BoringExtrasMenu` -> `KairoExtrasMenu`
  - `BoringBatteryView` -> `KairoBatteryView`
  - `BoringStatusMenu` -> `KairoStatusMenu`
  - `BoringFaceAnimation` -> `KairoFaceAnimation`
  - `createBoringNotchWindow` -> `createKairoWindow`
  - `BoringNotchXPCHelperProtocol` -> `KairoXPCHelperProtocol`
  - `BoringNotchXPCHelper` -> `KairoXPCHelper`
- **Constants:** `boringShelf` -> `kairoShelf`
- **Notifications:** `com.boringNotch.sharingDidFinish` -> `com.kairo.sharingDidFinish`
- **API paths:** `/auth/boringNotch` -> `/auth/kairo`
- **Settings:** GitHub URLs -> `wizlox/kairo-notch`, credits updated
- **Localizable.xcstrings:** All 16 locales updated for 5+ string keys
- **CI/Docs:** GitHub workflows, README, CONTRIBUTING, SECURITY, appcast.xml all updated
- **Directory renames:** `boringNotch/` -> `Kairo/`, `boringNotch.xcodeproj` -> `Kairo.xcodeproj`, `BoringNotchXPCHelper/` -> `KairoXPCHelper/`
- **File renames:** 10 Swift files renamed from Boring* to Kairo*
- **Header comments:** All ~100+ Swift files updated
- **Duplicate cleanup:** Removed stale subdirectory copies of files

### Phase 2: Voice Feedback Engine

Added real-time voice feedback for every action Kairo takes (BEFORE/DURING/AFTER pattern like Alexa/Siri):

**New file: `Kairo/KairoFeedbackEngine.swift`**
- `KairoFeedbackEngine.shared` — central voice + pill feedback hub
- `say(_ text:, pillText:, priority:)` — speak + show pill
- `flash(_ text:, duration:)` — pill-only, no speech
- `speak(_ text:)` — speech-only
- ElevenLabs TTS with system TTS (Daniel voice) fallback
- Posts `Notification.Name.kairoFeedback` for UI pill display
- Global shorthand: `let KairoFeedback = KairoFeedbackEngine.shared`

**New file: `Kairo/KairoWebSearch.swift`**
- `KairoSearchResult` model (title, snippet, url)
- `handleWebSearch()` — DuckDuckGo search -> Claude Haiku summarization -> spoken results -> open browser
- `searchWeb()` — DuckDuckGo Instant Answer API (free, no key needed)
- `summarizeResults()` — Claude Haiku 4.5 summarization
- `askClaude()` — direct AI responses for general questions

**New file: `Kairo/KairoCommandExecutor.swift`**
- `KairoIntent` model (intent, query, app)
- `execute()` — routes all intents through feedback-enabled handlers
- Full implementations with voice feedback:
  - `playYouTube` / `playSpotify` / `playAppleMusic`
  - `adjustVolume` / `toggleLights` / `toggleAC`
  - `cinemaMode` / `goodNight` / `awayMode`
  - `reportWeather` / `reportCalendar` / `reportTime`
  - `openApp` / `takeScreenshot` / `lockScreen`
  - `handleGeneralQuery`
- Home Assistant API integration via `callHomeAssistant(domain:service:entity:)`

**Modified: `Kairo/KairoVoice.swift`**
- Added `import AppKit` (was missing)
- Added TTS extension: `speak()`, `speakWithElevenLabs()`, `speakWithSystem()`

**Modified: `Kairo/KairoAppController.swift`**
- `routeIntent()` now delegates to `KairoCommandExecutor.shared.execute()`

**Modified: `Kairo.xcodeproj/project.pbxproj`**
- Added PBXFileReference + PBXBuildFile entries for all 3 new files
- Added to Sources build phase and Kairo PBXGroup

### Phase 3: UI Polish (Most Recent)

Modernized the entire UI across two files:

**`Kairo/KairoDesign.swift` changes:**
- Added `K.orange` (#FF9F0A), `K.pink` (#FF375F) colors
- Added `K.warmGlow` gradient (gold -> orange)
- Moved text color extensions (`kTextPrimary/Secondary/Tertiary/Muted`) from KairoServices.swift into KairoDesign.swift
- `KairoBounce` — added opacity fade on press (0.85)
- `KairoTabBar` — complete redesign:
  - SF Symbol icons per tab (waveform, command, house.fill, bubble.left.fill, bell.fill)
  - Selected tab shows icon + text label, others show icon only
  - Capsule pill shape instead of rounded rectangle
  - Haptic feedback on tab switch
  - 11px rounded font (was 9px monospaced)
- `KairoTab` — raw values now Title Case ("Now Playing" not "NOW PLAYING"), added `icon` computed property

**`Kairo/KairoNotchView.swift` changes:**
- **Idle clock** — 52pt ultra-light with gradient text + breathing cyan glow
- **Ambient cards** — `ultraThinMaterial` glass, gradient borders, title moved to top-right corner, 22pt primary text, 18pt icons, better label hierarchy
- **Commands grid** — Each command has unique color:
  - Cinema = violet, Spotify = spotify green, Music = pink
  - YouTube = red, Night = blue, Camera = orange
  - Lights = gold, Away = green, Brief = cyan
- **CmdCardView** — Color-tinted gradient icon backgrounds, `ultraThinMaterial`, thinner 0.5px borders
- **Device cards** — Gradient-filled icon circles, rounded fonts, descriptive status text (Connected/Standby/etc.)
- **Input bar** — Capsule shape, 12px rounded font, mic button triggers voice mode, material background
- **Chat bubbles** — 12px rounded font, more padding, softer backgrounds, larger avatars
- **Voice mode** — 48px orb (was 44), "Listening..." labels, taller 40px waveform, rounder typography, cleaner section labels
- **Notification pill** — 36px icons, 14pt title, rounded fonts, bounce button style, material glass
- **Response view** — Card background with cyan tint + border
- **Quick actions** — 40px circles, 10px spacing
- **Overall** — More breathing room (14px horizontal padding throughout), thinner borders (0.5px), `.rounded` design font everywhere

**`Kairo/KairoServices.swift` changes:**
- Removed text color extension block (moved to KairoDesign.swift)

---

## Project Structure (Key Files)

```
kairo-notch/
  Kairo.xcodeproj/           — Xcode project
  Kairo/                     — Main app source
    KairoApp.swift           — App entry point (@main)
    KairoDesign.swift        — Design system (colors K.*, animations, components)
    KairoNotchView.swift     — Main notch view (tabs, idle, commands, devices, chat, voice, notifs)
    KairoFeedbackEngine.swift — Voice + pill feedback hub (ElevenLabs TTS)
    KairoCommandExecutor.swift — Command handler with BEFORE/DURING/AFTER feedback
    KairoWebSearch.swift     — DuckDuckGo + Claude summarization
    KairoVoice.swift         — Mic recording + TTS playback
    KairoVoiceButton.swift   — Floating voice button + KairoVoiceEngine
    KairoAppController.swift — Browser/app/system control (AppleScript, YouTube API)
    KairoServices.swift      — Weather (OpenWeather) + Home Assistant services
    KairoSocket.swift        — WebSocket to backend (ws://localhost:8420/ws)
    KairoMorningBriefing.swift — Wake detection + AI briefing
    KairoNotifications.swift — Notification engine + history tab
    ContentView.swift        — Main notch content wrapper (gestures, hover, layout)
    components/
      Notch/
        NotchHomeView.swift  — Music player view (album art, controls)
    ...other inherited views from boringNotch
  KairoXPCHelper/            — XPC service for privileged operations
  mediaremote-adapter/       — MediaRemoteAdapter.framework
```

## API Keys (Environment Variables)

The app reads these from environment variables:

| Variable | Service | Required? |
|---|---|---|
| `ANTHROPIC_API_KEY` | Claude API (Haiku) for AI responses + search summarization | Yes for AI features |
| `ELEVENLABS_API_KEY` | ElevenLabs TTS for natural voice | Yes for voice (falls back to system TTS) |
| `ELEVENLABS_VOICE_ID` | ElevenLabs voice ID | No (defaults to pNInz6obpgDQGcFmaJgB) |
| `YOUTUBE_API_KEY` | YouTube Data API v3 for direct video playback | No (falls back to search URL) |
| `HOMEASSISTANT_URL` | Home Assistant base URL | Yes for smart home |
| `HOMEASSISTANT_TOKEN` | Home Assistant long-lived access token | Yes for smart home |
| `OPENWEATHER_API_KEY` | OpenWeather API | Yes for weather |

## Build & Run

```bash
cd /Users/wizlox/Developer/kairo-notch
xcodebuild -project Kairo.xcodeproj -scheme Kairo -configuration Debug build
```

Build output lands in DerivedData. To install:
```bash
# Quit running app first
osascript -e 'quit app "Kairo"'
# Copy to Applications
cp -R ~/Library/Developer/Xcode/DerivedData/Kairo-*/Build/Products/Debug/Kairo.app /Applications/
# Launch
open /Applications/Kairo.app
```

---

## What's Next (Planned Work)

### Immediate (UI Polish Continuation)
1. **Install the fresh build** — Copy the just-built app to /Applications and launch it
2. **NotchHomeView.swift** — The music player view (album art, controls) still uses the old boringNotch styling. Needs the same polish treatment: rounded fonts, better spacing, material backgrounds
3. **KairoNotifications.swift** — The `NotificationHistoryTab` view needs modernization to match the new design language
4. **Settings view** — Still has remnants of old design; needs Kairo branding polish
5. **KairoHeader** — The header shown when notch is open could use refinement

### Medium Term (Feature Work)
6. **Feedback pill integration** — The `KairoFeedbackEngine` posts `.kairoFeedback` notifications but the `KairoNotchView` doesn't yet listen for them and display the feedback text as a pill overlay. Wire this up.
7. **Kairo backend server** — The WebSocket connects to `ws://localhost:8420/ws`. Need to set up or document the backend that handles voice commands and intent classification.
8. **Morning briefing UI** — `KairoMorningBriefing.swift` has word-by-word animation but needs a dedicated display in the notch view.
9. **Smart home live state** — Device cards currently show hardcoded status. Wire them to `KairoHomeService` real-time state.
10. **Keyboard shortcut** — Voice activation via Cmd+Shift+K needs verification and possibly a global hotkey registration.

### Long Term
11. **macOS 26 Liquid Glass** — Many views already use `.glassEffect(.regular)`. When macOS 26 ships, verify `liquidGlass()` renders correctly on real hardware.
12. **Notification actions** — Reply/quick-action buttons in notification pills.
13. **Calendar integration** — Full EventKit integration for upcoming events display in idle screen.
14. **Multi-room audio** — Extend Denon AVR / HomePod control.
15. **Plugin system** — Allow third-party command extensions.

---

## Known Issues
- **SourceKit diagnostics** — Outside Xcode, SourceKit shows "Cannot find X in scope" for types defined in other files. This is because SPM packages aren't resolved by the CLI. **These are false positives** — the project builds successfully with `xcodebuild`.
- **Swift 6 concurrency warnings** — A few `sendable-closure-captures` warnings in KairoServices.swift. Pre-existing, not blocking.
- **NSSpeechSynthesizer deprecation** — Used as TTS fallback. Apple deprecated it but no replacement exists yet. Works fine on macOS 26.
- **`onChange(of:perform:)` deprecation** — A few uses of the old single-parameter onChange. Should migrate to two-parameter version eventually.

---

## Session Build Status
**Last build: SUCCESS** (2026-04-09)
All changes compile cleanly. App is ready to install and test.
