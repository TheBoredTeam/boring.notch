# CLAUDE.md

## The personal quest

This is a fork of **TheBoringNotch** (`TheBoredTeam/boring.notch`) that I'm customizing to make the MacBook camera notch behave exactly the way I want — and contributing the better changes back upstream as pull requests rather than living on a permanent fork.

Goals, roughly in order:

1. **Customize for myself first.** Whatever ergonomic, visual, or behavioral itch I have with the upstream app, I scratch it here.
2. **Stay mergeable with upstream.** Avoid sweeping refactors. Prefer additive, opt-in features (Defaults keys, toggles) so my fork can pull from upstream without conflicts.
3. **Upstream what's general.** If a change feels useful to other users (not just personal taste), open a PR against `TheBoredTeam/boring.notch` targeting the `dev` branch.
4. **Learn Swift/SwiftUI properly** along the way. This is my first Swift codebase, my first SwiftUI work, and my first open-source contribution.

## Working agreement with Claude

- **I'm new to Swift/SwiftUI.** When explaining code, lean on analogies and call out idioms I'd miss (e.g., `@State` vs `@Default`, `animatableData`, `AnimatablePair`).
- **Don't refactor unprompted.** A bug fix doesn't need surrounding cleanup. A one-shot feature doesn't need a helper layer. Match the existing style.
- **Customization features should be opt-in via `Defaults` keys** in `boringNotch/models/Constants.swift`, with toggles in `SettingsView.swift`. Keep upstream behavior intact when the toggle is off.
- **Build, install, and check the actual app** before claiming a change is done — type-checking is not the same as visual correctness for a UI app.
- **Clean up build artifacts** when wrapping a session (`build/`, `~/Library/Developer/Xcode/DerivedData/boringNotch-*`). They run ~1+ GB each.

## Build, install, test

All commands run from `/Users/yoorztruely/Desktop/boring.notch`. Full reference (rollback, uninstall, PR helpers) lives at `~/Desktop/boringNotch-commands.md`.

**Debug build:**
```bash
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -destination 'platform=macOS' build | grep -E "error:|BUILD"
```

**Release build (this is what I install over `/Applications/boringNotch.app`):**
```bash
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release -destination 'platform=macOS' -derivedDataPath build build | grep -E "error:|BUILD"
```

**Install Release over the existing app (requires ad-hoc re-sign because `MediaRemoteAdapter.framework` is pre-signed by another Team ID):**
```bash
pkill -x boringNotch
rm -rf /Applications/boringNotch.app
cp -R /Users/yoorztruely/Desktop/boring.notch/build/Build/Products/Release/boringNotch.app /Applications/boringNotch.app
codesign --force --deep --sign - /Applications/boringNotch.app
open /Applications/boringNotch.app
```

Without `codesign --force --deep --sign -`, the Release build crashes on launch due to a Team ID mismatch with the bundled framework.

## Codebase landmarks

- `boringNotch/models/Constants.swift` — all `Defaults.Key` definitions. Any new persisted setting goes here.
- `boringNotch/models/MusicControlButton.swift` — enum of media controls + `defaultLayout`, `minSlotCount`, `maxSlotCount`.
- `boringNotch/ContentView.swift` — top-level notch view; border overlay, hover/open state, animations live here.
- `boringNotch/components/Notch/NotchShape.swift` — `NotchShape` (fill), `NotchBorderShape` (border, left/bottom/right open path), `NotchUpperCurvesShape` (closed-state shoulders). All use `animatableData` so they animate smoothly with open/close.
- `boringNotch/components/Notch/NotchHomeView.swift` — the music controls toolbar; renders configured slots.
- `boringNotch/components/Settings/SettingsView.swift` — settings window; `Appearance` and `Advanced` sections share the `PresetAccentColor` helper.
- `boringNotch/components/Settings/MusicSlotConfigurationView.swift` — drag-and-drop slot configurator.
- `boringNotch/extensions/Color+AccentColor.swift` — accent + border color helpers, including `Color.effectiveBorder` / `NSColor.effectiveBorder` archiving.

## Conventions I've observed in this codebase

- **Persistence via `Defaults`**: `@Default(.keyName) var localName` in views; `Defaults[.keyName]` everywhere else.
- **Custom shapes**: implement `animatableData` (use `AnimatablePair` for multiple `CGFloat`s) so SwiftUI can interpolate during open/close springs.
- **Physical-notch detection**: `vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) }.map { $0.safeAreaInsets.top > 0 } ?? false`.
- **Open/close animation**: `vm.notchState` flips instantly on trigger, but the visible shape takes ~0.45s to settle (`spring(response: 0.45, dampingFraction: 1.0)`). Any state that should match the *visual* close, not the logical one, needs a delay (~0.7s is the empirically-tuned value).
- **Color archiving**: persist `NSColor` via `NSKeyedArchiver` → `Data` → `Defaults`. Restore with `NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from:)`.

## Customizations on this fork so far

- **Customizable notch border** (color + width). Off/Custom toggle + 8 presets + free color picker + 0.25–2.0 pt slider. Border traces left/bottom/right. Upper shoulder curves appear after close completes (0.7s delay) — only on physical-notch displays unless `cornerRadiusScaling` is on. Lives under **Settings → Appearance → Notch border**. Upstream PR: [TheBoredTeam/boring.notch#1267](https://github.com/TheBoredTeam/boring.notch/pull/1267).
- **7-slot media control layout** (was 5). Empty slots are filtered from the rendered toolbar so visible controls always center as a group regardless of where the user placed them. Existing users get migrated to the new slot limit when they open the configurator.

## Upstream / contribution flow

- Default branch upstream is `dev`, **not** `main`. Always target `dev` for PRs (their bot will flag it otherwise — fix with `gh pr edit <num> --repo TheBoredTeam/boring.notch --base dev`).
- Personal fork remote is named `fork` (not `origin`). Push feature branches there before opening a PR.
- The full PR submission command lives in `~/Desktop/boringNotch-commands.md`.
