# Feature Handoff: Pomodoro notch tab

## Original request

/private/tmp/boring-notch-pomodoro-handoff.md
implement the Pomodoro tab with strong UI polish, then run the feature critique gate before considering it complete.

Relevant handoff requirements from `/private/tmp/boring-notch-pomodoro-handoff.md`:
- Add Pomodoro as the third notch tab after Music and Shelf.
- Include basic Pomodoro functionality.
- Let the user customize work minutes and break minutes.
- Make the Pomodoro experience visually pleasing across its full lifecycle.
- Build/run the app so changes are visible in-app.
- Run feature critique before considering complete.

## Implementation summary

- Added a third notch tab: Music, Shelf, Pomodoro.
- Added `PomodoroView` with a shared `PomodoroTimerModel` for idle/focus/break/complete lifecycle, start/pause/resume/skip/reset actions, circular progress, phase-specific color states, and persisted work/break minute settings.
- Added a closed-notch live Pomodoro countdown so an active/paused/completed Pomodoro remains visible on the notch itself without reopening the tab.
- Distilled the closed-notch countdown after user feedback: it is now only simple centered text, with no capsule, colors, icon, glow, label, or progress ring.
- Tightened tab button sizing so all three icons fit in the left notch tab strip without clipping.
- Preserved the existing debug app path and Spotify debug callback configuration when reinstalling the rebuilt app.

## Changed files

- `boringNotch/components/Notch/PomodoroView.swift`: new polished Pomodoro UI and timer model.
- `boringNotch/components/Tabs/TabSelectionView.swift`: adds Music/Shelf/Pomodoro order.
- `boringNotch/components/Tabs/TabButton.swift`: compacts tab icon buttons to fit three tabs.
- `boringNotch/enums/generic.swift`: adds `.pomodoro` notch view.
- `boringNotch/ContentView.swift`: renders `PomodoroView` for the Pomodoro tab and renders the live closed-notch countdown chip when a Pomodoro session is active/paused/complete.
- `boringNotch/models/Constants.swift`: adds persisted work/break minute defaults.
- `boringNotch.xcodeproj/project.pbxproj`: includes the new Swift file in the app target.

## How to test

- Build:
  - `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/boring-notch-pomodoro-derived build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO`
- Existing package tests:
  - `cd SpotifyAdDampenerCore && swift test`
- Installed-app smoke:
  - Copy `/tmp/boring-notch-pomodoro-derived/Build/Products/Debug/boringNotch.app` to `/Applications/Boring Notch Spotify Debug.app`.
  - Set bundle id to `theboringteam.boringnotch.spotifydebug` and URL scheme to `boringnotch-debug`.
  - Ad-hoc codesign and launch `/Applications/Boring Notch Spotify Debug.app`.
  - Hover the notch; verify three tabs render: Music, Shelf, Pomodoro.
  - Click the Pomodoro/timer tab; verify the timer card shows 25:00 Ready, Focus/Break steppers, Start/Break/Reset controls, and phase-color styling.
  - Click Start/Resume; verify the control and timer state update interactively.
  - Close the notch while the Pomodoro is active; verify the closed notch itself shows only the live text countdown, with no colorful capsule/icon/progress ring.

## Tests run

- `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/boring-notch-pomodoro-derived build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO`: PASS after the simple text countdown distillation. Warning only: existing MediaRemoteAdapter framework built for macOS 15 while target is macOS 14.
- `cd SpotifyAdDampenerCore && swift test`: PASS, 20 tests passed.
- Installed debug app launch/readback after simple text countdown distillation: PASS, process `/Applications/Boring Notch Spotify Debug.app/Contents/MacOS/boringNotch` running; bundle id `theboringteam.boringnotch.spotifydebug`; URL scheme `boringnotch-debug`.
- Native screenshot smoke after simple text countdown distillation:
  - `/tmp/boring-notch-simple-text-countdown.png`: showed the closed notch displaying only simple white text countdown `59:57`, with no colored capsule/icon/progress ring.
  - `/tmp/boring-notch-simple-text-countdown-2.png`: showed the closed notch displaying only simple white text countdown `59:19`, proving it remains visible and continues counting down.
- Native screenshot smoke before text distillation:
  - `/tmp/boring-notch-pomodoro-open-countdown-feature.png`: showed Pomodoro UI with 60:00 Ready and Start/Break/Reset controls.
  - `/tmp/boring-notch-closed-countdown-running.png`: showed the closed notch displaying the earlier red/accented Focus chip with `59:57` after starting the timer.
  - `/tmp/boring-notch-closed-countdown-running-2.png`: showed the earlier chip at `59:32`.
- Native screenshot smoke before R1 fix:
  - `/tmp/boring-notch-top-crop-3tabs.png`: showed three tab icons.
  - `/tmp/boring-notch-after-timer-hover-content.png`: showed Pomodoro UI with 25:00 Ready, work/break settings, Start/Break/Reset controls.
  - `/tmp/boring-notch-pomodoro-running.png`: showed interactive focus state after clicking the primary control.

## Critique fix cycle

- Initial critique report: `.hermes/reviews/pomodoro-notch-tab/critique-report.md`, verdict `REQUEST_CHANGES`.
- Required R1 fix applied in `PomodoroView.swift`: changed work/break minute settings from Defaults-only computed properties to `@Published private(set)` stored model state, added `setWorkMinutes(_:)` and `setBreakMinutes(_:)`, and kept Defaults persistence plus phase reset behavior for idle/paused applicable phase.
- Rebuilt successfully after fixing a Swift initialization issue by using a local `initialWorkMinutes` before all stored properties are initialized.

## Git info

- Branch: `main`
- Commit SHA, if committed: not committed
- Diff base: current working tree against `HEAD` (`e3d7b68`)

## Frontend/backend/database notes

- SwiftUI notch UI only.
- No backend/database changes.
- Settings persist through Defaults keys: `pomodoroWorkMinutes`, `pomodoroBreakMinutes`.

## Reviewer focus areas

- Verify the Pomodoro tab is reachable as the third tab and the tab strip still fits around the physical notch area.
- Inspect timer lifecycle correctness: idle, focus, paused focus, break, paused break, complete, skip/reset.
- Inspect settings persistence and range clamping.
- Inspect UI polish/readability in compact notch dimensions.
- Check for SwiftUI/macOS lifecycle problems with `Timer.scheduledTimer` in a shared observable model.
- Confirm project file includes new Swift source.

## Fix cycle notes

Initial review request.
