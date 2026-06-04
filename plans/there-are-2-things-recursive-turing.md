---
constellagent:
  codingAgent: composer-2.5-fast
  buildHarness: cursor
---
# Plan: Fix Pi markdown rendering + redesign the peek aurora gradients

## Context

Two separate polish problems in the Pi agent UI:

1. **Markdown rendering is "annoying" where it adds nothing.** `PiAgentView.answer` always pipes the streamed transcript through `PiMarkdownView`, which re-parses block-level markdown (headings, lists, fenced code, blockquotes) on every streamed delta. For short, plain-prose answers this applies heavy block styling where none is warranted, and during streaming the block layout reflows/flickers as partial lines flip between paragraph → heading → list. The user wants to **keep** markdown + tappable deeplinks, but only render the styled version *when it's actually needed* — clean plain text otherwise.

2. **The peek aurora gradients look bad.** The collapsed running-agent strip (`PiPeekView`) draws a logo `glow` (RadialGradient) and a right-edge `edgeBloom` (EllipticalGradient). They read as a flat, muddy single-color haze (see screenshot). The user wants a better-looking gradient, researched via nia and previewed as HTML options before any SwiftUI is written.

**Hardware (user):** the user runs **macOS 15+**, so SwiftUI's native `MeshGradient` is available on their machine and is the look we should design toward — it's the cleanest path to a real aurora and what the redesign should *lead* with.

**Constraint found via nia:** the project's **deployment target is still `MACOSX_DEPLOYMENT_TARGET = 14.0`** (confirmed at six build configs in `boringNotch.xcodeproj/project.pbxproj`). `MeshGradient` requires macOS 15, so on the shipped 14.0 floor it must sit behind `#available(macOS 15, *)` with a macOS-14 fallback that still looks good. Two ways to resolve this:
- **(A — recommended) Hero + fallback.** Make native `MeshGradient` the primary look behind `if #available(macOS 15, *)`, with a layered radial/angular fallback for macOS 14. The user sees the hero look; macOS-14 users still get a tasteful gradient. No project setting changes.
- **(B) Bump the floor to 15.0.** Set `MACOSX_DEPLOYMENT_TARGET = 15.0` across the configs and drop the fallback entirely — simpler code, but cuts off macOS 14 users. *Decide before Step 2b.*

**Design skills selected (via `/find-skills` + `/nia`):** the ecosystem gradient skills (`nexu-io/...gradient` 186 installs, `patricio0312rev/...tailwind-gradient-builder` 175, `bergside/...gradient` 156) are all low-install and web/WinForms-oriented — none SwiftUI-relevant. The best fit is the already-installed local **`emil-design-eng`** (Emil Kowalski UI-polish/taste philosophy) for the color/stop/contrast judgment, paired with **`web-animation-design`** for the bloom motion (easing, reduced-motion). nia's indexed corpus has no rich native-`MeshGradient` sample to cite, so the mesh recipe below comes from the SwiftUI API directly. Use `emil-design-eng` when picking final stops/opacities and `web-animation-design` when tuning the bloom timing.

---

## Part 1 — Markdown: render styled only when needed

**Decision (recommended UX, user-approved "combined"):**
- **While the turn is streaming** (`pi.isRunning`): render the transcript as a single inline-styled `Text` — no block parsing, no reflow. Bold/italic/inline-code + autolinked URLs still apply, so deeplinks stay tappable.
- **When the turn is settled** (not running, transcript non-empty):
  - If the transcript contains **genuine block markdown** (heading `#`, fenced code ```` ``` ````, list marker, blockquote `>`, or table `|`) → render the full `PiMarkdownView`.
  - Otherwise → keep the lightweight inline `Text` (clean prose, tappable links, no block noise).

**Why:** kills the streaming flicker and the unwanted heading/list/code-box treatment on conversational answers, while preserving real formatting for genuinely structured replies and keeping every link tappable in all states.

### Changes

- **`boringNotch/components/Pi/PiMarkdownView.swift`**
  - Add a lightweight inline-only view (e.g. `PiInlineText` or a static helper) that renders a single `Text(Self.inline(text, accent:))` with `.textSelection(.enabled)`. Reuse the existing `static func inline(_:accent:)` (lines 102–127) — it already handles bold/italic/inline-code + `autolink` of bare URLs. No new parsing code.
  - Add a cheap detector, e.g. `static func hasBlockStructure(_ raw: String) -> Bool`, that scans lines for a leading `#`/```` ``` ````/`- `/`* `/`+ `/`N.`/`> ` or a `|` table row. Reuse the existing `headingMatch` / `listItem` helpers (lines 247–277) rather than duplicating their logic.

- **`boringNotch/components/Pi/PiAgentView.swift`** (`answer`, lines 318–329)
  - Replace the unconditional `PiMarkdownView(text: pi.transcript)` branch with a selector:
    - `pi.transcript.isEmpty` → placeholder (unchanged).
    - `pi.isRunning || !MDBlock.hasBlockStructure(pi.transcript)` → lightweight inline `Text`.
    - else → `PiMarkdownView(text: pi.transcript)`.
  - Keep the existing crossfade `.animation(...)` and the stick-to-bottom scroll behavior untouched.

- **CTA / connection prompt:** no change. `connectionPrompt(_:)` (lines 278–310) is independent of markdown and already covers connection links; it stays as-is.

---

## Part 2 — Peek aurora gradient redesign (HTML preview → SwiftUI)

Target code: **`boringNotch/components/Pi/PiPeekView.swift`** — `glow` (lines 140–163, RadialGradient) and `edgeBloom` (lines 169–196, EllipticalGradient). Color inputs already exist: `accentColor` (toolkit accent or app accent), `companionColor` (accent blended 0.6 toward `.systemIndigo`), driven by `pi.isRunning` / `toolCallActive`.

### Step 2a — Generate HTML option mockups (first execution step)
Write a single self-contained `boring-notch-gradient-options.html` mocking the peek strip (black notch, logo-left, "Bash" + wave-right) on a desktop-like backdrop, rendering the candidates side by side, and send it via SendUserFile for the user to pick. **Lead with the mesh look** since the user is on macOS 15+; the CSS approximations of the layered options exist to show the macOS-14 fallback quality.

Candidate directions, in priority order:
1. **★ Native-mesh aurora (hero / default)** — the look the `MeshGradient` path will render: a soft 3×3 (or 3×2) field of overlapping color blobs, toolkit `accentColor` and `companionColor` woven through warm/cool control points, no hard edges, gentle drift. Approximate in HTML with 3–4 offset `radial-gradient`s blended `screen`/`plus-lighter` over black so the side-by-side reads true to the SwiftUI result.
2. **Refined two-hue aurora** — the current elliptical concept but additive blend (`screen`/`plus-lighter`), tighter color stops, less blur haze, a faint second offset layer for depth. (Doubles as part of the macOS-14 fallback.)
3. **Layered radial bloom (mesh-like)** — 2–3 offset radial gradients with screen blend → fake mesh depth on macOS 14. This is the concrete fallback the `#available` else-branch ships.
4. *(optional)* **Angular light sweep** — angular/conic gradient for a moving-light feel, if the user wants motion in the resting (non-tool) state.

Use the **`emil-design-eng`** sensibility when choosing stops/opacities (additive light wants fewer, more saturated stops and restraint on blur), and **`web-animation-design`** for any animated preview. User picks one (or a blend) before any Swift changes.

### Step 2a-bis — Source the colors from the toolkit logo palette (root-cause fix)
**The muddiness is a color-sourcing bug, not just a blur problem.** `PiAgentManager.adoptLogo` (PiAgentManager.swift:417–423) calls `NSImage.averageColor` and feeds the single averaged result through `legibleTint` into `toolkitAccent`; `companionColor` then blends that one hue 60% toward indigo. Averaging a multi-color Composio logo collapses it to mud — verified against the live assets:

| toolkit | logo palette (from `logos.composio.dev/api/<slug>`) | today's `averageColor`+`legibleTint` |
| --- | --- | --- |
| gmail | `#d83030 #3078f0 #30a848 #f0a800` | `#c8b1a5` (beige mud) |
| googlecalendar | `#3078f0 #f0a800 #30a848 #1860c0` | `#bacfd3` (grey-blue) |
| slack | `#d81848 #18a878 #d8a818 #30c0f0` | `#bfc3b7` (grey-green) |
| linear | `#7890f0` (single) | `#bac7ff` (fine — already one hue) |
| notion / github | greys only | `#d3d3d3` / `#86898c` |

**Change:** extract a small **palette** from the same cached logo instead of one average. Add `NSImage.dominantColors(max:)` (area-weighted bucketed pass, drop transparent + near-white/near-black background — the existing `averageColor` pixel-walk in NSImage+Extensions.swift:19–106 is the template) and publish `toolkitPalette: [NSColor]` from `adoptLogo`, keeping `toolkitAccent = palette.first` for back-compat. Three cases:
- **2+ saturated colors** (gmail, calendar, slack, drive) → assign the dominant colors directly to the mesh control points; the aurora *is* the brand.
- **1 saturated color** (linear) → pair it with a lighter/darker shade of itself for internal mesh variation.
- **0 saturated colors** (notion, github) → too desaturated to carry an aurora; keep today's behavior — brand tone + indigo `companionColor`.

`PiPeekView` then feeds `pi.toolkitPalette` into the mesh colors. This is what makes the redesign *adaptive per app* rather than a prettier version of the same mud.

### Step 2b — Implement the chosen look in `PiPeekView`
Resolve the macOS-15 question (Context option A vs B) first, and wire in the palette from Step 2a-bis. Assuming **A (hero + fallback)**:

- **`glow` and `edgeBloom` become `@available`-gated.** Wrap each in a small `@ViewBuilder` that returns a native `MeshGradient` on macOS 15 and the layered-radial version on macOS 14, e.g.:
  ```swift
  @ViewBuilder private var auroraFill: some View {
      if #available(macOS 15, *) {
          MeshGradient(
              width: 3, height: 3,
              points: meshPoints,            // animated control points (see below)
              colors: meshColors             // accentColor / companionColor woven with .black corners
          )
      } else {
          // existing RadialGradient/EllipticalGradient layered in a ZStack
          // with .blendMode(.screen)/.plusLighter, retuned stops/opacities/blur
      }
  }
  ```
- **Mesh recipe:** a 3×3 grid (9 points / 9 colors). Corner colors stay near-black (so the aurora bleeds into the notch instead of forming a hard rectangle); the interior/edge points carry `accentColor` and `companionColor` at varying opacity. Drive a couple of the non-corner `points` off `toolCallActive` (and optionally a `TimelineView` phase) so the field breathes — corners stay pinned to keep the silhouette stable. Clamp every point component to `[0, 1]`.
- **Additive feel:** keep the mesh in a `ZStack` over black and apply `.blendMode(.plusLighter)` (or `.screen`) plus the existing `.blur` so it reads as light, not paint — same additive principle as the macOS-14 fallback, so the two paths look like siblings.
- **Preserve all existing animation/state plumbing:** `pi.isRunning`, `toolCallActive`, `reduceMotion`, `Motion.glowBloom`, the scale/opacity transitions, and `.allowsHitTesting(false)`. Under Reduce Motion, hold the mesh `points` static (no drift) and keep only the opacity/scale bloom.
- **Keep the two-hue identity** (toolkit `accentColor` → `companionColor`) so per-app flair (gmail red→violet, calendar blue→indigo) still reads in both the mesh and fallback paths.

If the user chooses **B (bump to 15.0)** instead, drop the `#available` branches and the layered fallback entirely — `glow`/`edgeBloom` become straight `MeshGradient`s — and update `MACOSX_DEPLOYMENT_TARGET` to 15.0 across the six configs as a prerequisite step.

---

## Files touched
- `boringNotch/components/Pi/PiMarkdownView.swift` — add inline-only renderer + `hasBlockStructure` detector (reuse existing `inline`, `headingMatch`, `listItem`).
- `boringNotch/components/Pi/PiAgentView.swift` — gate styled vs inline rendering in `answer`.
- `boringNotch/components/Pi/PiAgentManager.swift` — `adoptLogo` publishes `toolkitPalette: [NSColor]` (dominant colors) instead of one averaged `toolkitAccent`.
- `boringNotch/extensions/NSImage+Extensions.swift` — add `dominantColors(max:)` alongside the existing `averageColor`.
- `boringNotch/components/Pi/PiPeekView.swift` — redesign `glow` + `edgeBloom` around native `MeshGradient` (macOS 15 hero) + layered-radial fallback (macOS 14), driven by `pi.toolkitPalette`.
- *(option B only)* `boringNotch.xcodeproj/project.pbxproj` — bump `MACOSX_DEPLOYMENT_TARGET` 14.0 → 15.0 across the six configs.
- `boring-notch-gradient-options.html` — throwaway preview artifact (not committed).

## Verification
- **Build:** `xcodebuild -scheme boringNotch -configuration Debug build` (or build in Xcode). Note: per saved memory, sign without the hardened-runtime flag on this Mac — ad-hoc + hardened runtime crashes the app.
- **Markdown, streaming:** run an agent turn that returns plain prose → confirm no block reflow/flicker mid-stream and clean text after; run one that returns a list/code block → confirm full markdown renders once settled. A URL/connection link is tappable in both cases.
- **Markdown, edge:** verify the CTA "Connect …" capsule still appears and works on a `connection_required` turn.
- **Gradient (macOS 15 hero):** on the user's machine, trigger a running turn (and a tool call) → confirm the native `MeshGradient` aurora matches the approved mockup, blooms on `toolCallActive`, the mesh field breathes (corners stay pinned, no hard rectangle edge), collapses when the run ends, and holds static under Reduce Motion.
- **Gradient (macOS 14 fallback):** if shipping option A, build/run against a macOS-14 target (or temporarily force the `else` branch) → confirm the layered-radial fallback still reads as a tasteful sibling, not a regression. Skip if shipping option B.
