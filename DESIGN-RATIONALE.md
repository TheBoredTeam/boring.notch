# Kairo — Design Rationale

A short read on **why** the redesign looks the way it does, what was
preserved, and what's intentionally idiomatic to macOS vs iOS.

## TL;DR

Kairo is a **macOS** app that lives in the **MacBook camera notch**.
The brief described it as a "Dynamic Island app" — that's iOS. They're
visually adjacent but technically unrelated (the macOS notch is just
screen real estate; the iPhone Dynamic Island is a system-managed
Live Activity surface). The redesign treats "Liquid Glass" as a
**stylistic direction** that applies to both platforms via the macOS 26 /
iOS 26 design language, while respecting the actual platform differences.

There are **two visual identities** in the system, on purpose:

1. **Kairo (default)** — Apple-native: deep black surfaces, orange
   accent, blue orb, thin-material glass, SF Pro typography, 4pt grid.
2. **Plasma (preserved)** — the Hologram orb's cyan/purple/pink swirl
   and the legacy `KairoNotchView`'s cyan accents. These have been
   the assistant's "voice" since the BoringNotch fork. They aren't
   flattened to the Kairo palette — they're treated as **character**,
   the way a brand has multiple sub-marks.

The new design system harmonizes everything (light/dark, typography,
spacing, motion) without erasing what makes each surface itself.

## What was redesigned

| Phase | Surface | Files | Notes |
|---|---|---|---|
| 1 | Design system foundation | `DesignSystem.swift`, `Showcase.swift` | Tokens, glass material, 3 anchor components, side-by-side palette previews |
| 2 | Note window | `NoteShell` + 5 components | First full application of the new tokens |
| 3 | Orbie | `OrbieShell` + 7 view types | The new floating persona — same tokens, glass-backed |
| 4 | Hologram | `KairoHologramOrb`, `KairoHologramWindow` (chrome only) | Plasma sphere preserved; chrome harmonized |
| — | Legacy notch | `KairoDesign.swift` (palette bridge), `KairoNotchView` (input bar) | K palette now light/dark adaptive — notch gains light mode without a 1381-line refactor |
| 5 | iOS companion | `KairoiOS/` scaffold | Dynamic Island layouts + companion app; mirrors the macOS tokens |

## Key decisions

### 1. Two palettes, not one

The brief said "make it premium / Apple-native and visually distinct
from the original." Two palettes coexist because **both have value**:

- The plasma identity is what made early users say "this looks like
  Jarvis" — it's already premium in its own register, just not
  "Apple-native."
- The Kairo orange + glass is Apple-native — flat, calm, system-y.

Flattening one into the other would lose something. Letting both live
makes Kairo feel like a system, not a single screen.

The tokens in `Kairo.Palette` are the **system default**. The plasma
colors (cyan/purple/pink) are scoped to specific surfaces — the orb
and the legacy notch — where they're the **character** of that surface.

### 2. Glass via `Material`, not `.glassEffect()`

macOS 26's `.glassEffect()` modifier is new and shiny but its layering
behavior is still rough at the time of writing. The design system uses
SwiftUI's built-in `Material` (`.ultraThinMaterial`, `.thinMaterial`,
`.regularMaterial`, `.thickMaterial`) with a manual `glassTint` overlay
+ a 0.5pt `glassStroke` hairline. This:

- Works back to macOS 12 if we ever need to lower the target
- Is predictable across light + dark
- Stacks cleanly without the new modifier's compositing surprises

If a future macOS release proves `.glassEffect()` stable enough, the
modifier in `DesignSystem.swift` is the single place to swap it in.

### 3. Light/dark via `Color.adaptive`

iOS has `Color(light:dark:)`; macOS doesn't. We define a single
`Color.adaptive(light:dark:)` helper that wraps `NSColor`'s dynamic
provider. Every token in `Kairo.Palette` resolves through it. The
dark values are the original BoringNotch defaults — nothing visually
moved for existing users in dark mode; light mode is new.

### 4. Typography is a **scale**, not a free-for-all

Every type token resolves through `Kairo.Typography.*`. The scale is
10 sizes, capped — `display / title / titleSmall / body / bodyEmphasis /
bodySmall / caption / captionStrong / mono / monoSmall`. SF Pro Text and
Display are inferred from size (Apple's heuristic: ≥20pt → Display).
Mono is reserved for time, percentages, IDs, debug — not body copy.

This replaces the ad-hoc `.system(size: 12, weight: .medium)` that was
sprinkled through every view file before.

### 5. The 4pt grid is non-negotiable

`Kairo.Space.xxs(2) → xxxl(48)`. All paddings, all gaps, all spacing
flows through tokens. The grid is consistent enough that you can tell
when something is off, which is the actual point of having a grid.

### 6. Anchor components, not a full component library

Three components (`KairoGlassPanel`, `KairoPill`, `KairoCard`) cover
~80% of the new surfaces. Building more components ahead of need is
how design systems become bloated. The pattern is: when a third surface
needs the same composition twice, we lift it into a component. Until
then, the tokens are enough.

### 7. The legacy notch was bridged, not rewritten

`KairoNotchView` is 1381 lines and uses `K.cyan` / `.kairoSpring` —
a parallel mini-design-system from before the rebrand. Rewriting it
line-by-line would take many sessions and risk regressing animations
that already work.

Instead: `KairoDesign.swift` was bridged. `K.bg / K.pill / K.text /
K.muted` are now `Color.adaptive`. The notch gains light-mode support
**automatically**, with zero changes inside the 1381-line view. The
cyan/blue/violet accent identity is preserved on purpose (same logic
as the Hologram's plasma).

Full visual-language refactor of the notch remains a future phase.

### 8. Hologram chrome was refined, plasma was untouched

The Hologram's swirling cyan/purple/pink plasma sphere — animated
across 5 layered angular gradients with orbiting sparks and a
specular highlight — **is the assistant's face**. It would be a
mistake to repaint it in Kairo orange. What needed work was the
**chrome around it**: the display panel's glass surface (now proper
`.regularMaterial` + scrim + `glassTint`), the typography (now
`Kairo.Typography.mono` for the scan-line text), and the floating
orb's notification + now-playing badges (now consistent glass +
tokens). The plasma stays.

### 9. macOS notch ≠ iPhone Dynamic Island

The brief conflated these. They're different:

- **macOS notch**: physical bezel cutout on M-series MacBooks. The
  area around it is just normal screen real estate. Kairo positions
  a custom `NSWindow` there. No system API.
- **iPhone Dynamic Island**: system-managed Live Activity surface
  with three layouts (compact / expanded / minimal). Apps describe
  state via `ActivityKit`; the system renders. No custom `UIWindow`.

The macOS redesign treats "Dynamic Island" as **stylistic
inspiration** — pill shapes, glass materials, compact-to-expanded
morphs. The iOS companion (scaffolded in `KairoiOS/`) implements the
**real** Dynamic Island via `ActivityConfiguration { ... } dynamicIsland: { ... }`
with all four regions.

### 10. The pivot from "backend assistant" to "in-process Kairo"

Behind the design work, there's a quieter shift: Kairo used to route
voice through `http://localhost:8420` (a separate Python backend).
The new pivot brings everything in-process — `OllamaClient`, the
tiered tool executor (8 tools), short and long-term memory, the
Orbie persona. The Brain pipeline is now wired into `AppDelegate`
and reachable via `DebugMenu → Test Brain` for verification. Voice
input (wake word) is still stubbed; F5-via-`KairoVoiceTrigger` still
routes to the legacy backend.

## What was deliberately *not* changed

- The plasma sphere itself (`KairoHologramOrb.body`)
- The notch's voice mode overlay, chat tab, devices tab, commands tab
  (they work; full notch refactor is its own session)
- The K-namespace gradients (`K.gradient`, `K.cyanBlue`, `K.warmGlow`)
- The MicBar / MusicBar cyan-purple gradients in the hologram window
- The hardcoded Spotify / Apple Music / YouTube brand colors

These are character / brand identity, not surface-level styling.

## What's still open

- Full refactor of `KairoNotchView` (1381 LOC)
- iOS target setup in Xcode (the scaffold is ready; targets need to
  be added in the Project Navigator — see `KairoiOS/README.md`)
- Real pairing between macOS and iOS (currently sample data on iOS)
- Voice wake word — `KairoWakeWord` is still a Porcupine TODO
- 50+ Swift 6 Sendable warnings (these become errors when we move
  to Swift 6 language mode)
- Onboarding + Settings sweep with the new tokens

## File map

```
Kairo/Resources/
├── DesignSystem.swift       Phase 1 — tokens, glass, anchor components
└── Showcase.swift           Phase 1 — Xcode-preview-only design reference

Kairo/Note/                  Phase 2 — full redesign (6 files)
Kairo/Orbie/                 Phase 3 — full redesign (8 files)

Kairo/KairoHologramOrb.swift Phase 4 — chrome only; plasma preserved
Kairo/KairoHologramWindow.swift

Kairo/KairoDesign.swift      Legacy palette bridged to adaptive
Kairo/KairoNotchView.swift   Input bar uses adaptive text color

KairoiOS/                    Phase 5 — companion + Dynamic Island scaffold

DESIGN-RATIONALE.md          You are here
```
