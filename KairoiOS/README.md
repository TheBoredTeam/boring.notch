# KairoiOS — companion app + Live Activity

This folder is a **scaffold** for the iOS companion target. The source files
are intentionally not yet added to the Xcode project — adding a new target
is best done from Xcode itself.

## What's here

```
KairoiOS/
├── KairoiOSApp.swift                   ← @main entry for the iOS app
├── DesignSystem/
│   └── KairoTokens.swift               ← Mirrored design tokens (iOS-flavored)
├── LiveActivity/
│   ├── KairoActivityAttributes.swift   ← ActivityAttributes definition
│   └── KairoActivityWidget.swift       ← WidgetBundle + Dynamic Island layouts
└── Views/
    └── CompanionRootView.swift         ← Companion app root + view model
```

## Why two targets

iOS companion apps need:

1. **An iOS app target** — UIKit-based, hosts the SwiftUI views, owns the
   `Activity<…>` lifecycle (start / update / end).
2. **A widget extension target** — separate process, runs only when the
   system asks it to render. Hosts the `WidgetBundle` and the Dynamic
   Island layouts.

`KairoActivityAttributes.swift` must be compiled into **both** targets
(the app starts/updates activities, the widget renders them).

## Adding the targets in Xcode

Open `Kairo.xcodeproj` and:

1. **File → New → Target → iOS → App**
   - Product name: `KairoiOS`
   - Interface: SwiftUI
   - Language: Swift
   - Bundle identifier: `com.kairo.ios` (or your existing prefix `+ .ios`)
   - Drag this folder's `KairoiOSApp.swift`, `DesignSystem/KairoTokens.swift`,
     `LiveActivity/KairoActivityAttributes.swift`, and `Views/` into the new
     target's group. Make sure they're added to the `KairoiOS` target only
     (NOT the macOS `Kairo` target).

2. **File → New → Target → iOS → Widget Extension**
   - Product name: `KairoiOSWidget`
   - Include Live Activity: ✓
   - Drag `LiveActivity/KairoActivityWidget.swift` and `KairoTokens.swift`
     and `KairoActivityAttributes.swift` into the new target's group.
     `KairoActivityAttributes.swift` must be in **both** targets (use the
     "Target Membership" inspector).

3. **Capabilities → Live Activities**
   - In the iOS app target's `Info.plist`, add:
     - `NSSupportsLiveActivities` = `YES`
     - `NSSupportsLiveActivitiesFrequentUpdates` = `YES` (optional, lets
       you push faster updates while listening / speaking)

4. **Deployment target**
   - iOS 16.2+ for Live Activities; iOS 17+ recommended for the
     `ActivityContent` API used in `CompanionViewModel.start()`.

## Visual design

The companion follows the same design system as the macOS app
(`Kairo/Resources/DesignSystem.swift`):

- **Palette**: Obsidian — adaptive black/white surfaces, orange accent,
  blue orb. Light + dark.
- **Typography**: SF Pro Display/Text/Mono — `Kairo.Typography.display`
  on down through `mono`.
- **Spacing**: 4pt grid (`Kairo.Space.xxs` → `xxl`).
- **Radius**: Same scale (`xs` → `lg`).

Until both targets share code through a Swift package, the iOS tokens
live in `DesignSystem/KairoTokens.swift` and must be kept in sync with
the macOS `Kairo/Resources/DesignSystem.swift`.

## Live Activity layouts (Dynamic Island)

| Region            | Content                                    |
|---                |---                                         |
| Compact leading   | Orb badge (blue gradient sphere, 18pt)     |
| Compact trailing  | Mode glyph (•, …, K, ♪) in mode tint       |
| Minimal           | Tinted circle + "K" glyph                  |
| Expanded leading  | Orb badge, 28pt                            |
| Expanded trailing | State pill (dot + label)                   |
| Expanded center   | Primary + secondary text                   |
| Expanded bottom   | "John's Mac" + relative timestamp          |

Modes: `idle / listening / thinking / speaking / nowPlaying`. Tint colors
match the macOS palette — orange for active states, success green for
now playing, orb-blue for idle / thinking.

## Pairing (out of scope for the scaffold)

`CompanionViewModel` currently returns sample data. Real pairing would
involve:

- Bluetooth / local-network discovery of the Mac
- An authenticated WebSocket session to the Mac's `KairoWebSocketServer`
  (already running on port `8420`)
- Mirroring `OrbieController.mode` → `KairoActivityAttributes.State.Mode`
  for live updates

That belongs to a future phase.
