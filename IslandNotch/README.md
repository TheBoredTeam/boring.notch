# IslandNotch

> **Ported into this fork.** This is a self-contained macOS app vendored from the
> `constellagent` project. It is independent of boring.notch's own target — it
> ships its own `IslandNotch.xcodeproj`, `project.yml`, and `BuildSupport/`, and
> does not modify boring.notch. Build it on its own:
>
> ```bash
> cd IslandNotch
> # optional, regenerates the project from project.yml:
> #   brew install xcodegen && xcodegen generate
> open IslandNotch.xcodeproj            # then Run the IslandNotch scheme
> # or headless:
> xcodebuild -scheme IslandNotch -configuration Debug build
> ```
>
> Signing: copy `BuildSupport/PrivateOverrides.xcconfig.example` →
> `PrivateOverrides.xcconfig` and set your `DEVELOPMENT_TEAM` (gitignored).

A lightweight macOS menu-bar / notch app that captures a screenshot with a
hotkey, parks it in a floating "Dynamic Island"-style shelf under the notch, and
makes the screenshot trivially pasteable into whatever **local CLI coding agent**
you're running (Claude Code, Codex, …).

> **The file path is the entire integration.** There is no server, no upload, no
> MCP, no tunnel, no API key. The app captures a PNG to a folder and puts a
> pasteable payload (the path, or the image bytes) on the clipboard. Your agent
> reads the local file natively.

```
double-⌘ (or your shortcut)
   → screencapture -i → ~/Desktop/island-shots/<timestamp>.png  (+ index.json)
   → thumbnail appears in the floating notch shelf
       • left-click  → copy payload to clipboard
       • right-click → Quick Look the full-res PNG (offline)
   → paste into Claude Code / Codex
```

## Features

- **Notch shelf** — a floating, non-activating panel under the notch (via
  [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)); a top-center
  floating pill is used automatically on Macs without a notch. Expands on hover.
  Left-click thumbnails to copy; right-click the shelf for capture / Quick Look.
- **Two capture hotkeys** — a configurable global chord
  ([KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts),
  default ⌘⇧7) and an optional **double-tap ⌘** gesture (global `CGEventTap`).
- **Drag / throw images in** — drop image files onto the shelf; they're copied
  into the shots folder and indexed like a capture.
- **Auto-copy, your way** — choose which capture sources auto-copy to the
  clipboard (default: double-⌘ and the chord; drag-drops are manual).
- **Per-agent clipboard payload** — path, `look at <path>`, or raw image bytes,
  selectable per agent.
- **Quick Look** — right-click a thumbnail for a full-res, offline preview.
- **Housekeeping** — optional "delete shots older than N days" sweep.

## Architecture

```
macos/
├── IslandNotch.xcodeproj            # Hand-written, folder-synchronized (objectVersion 77)
├── project.yml                      # Optional XcodeGen spec (regenerates the project)
├── BuildSupport/                    # Base.xcconfig, Info.plist, entitlements, signing template
└── IslandNotch/
    ├── IslandNotchApp.swift         # @main; Settings scene only (LSUIElement agent app)
    ├── AppDelegate.swift            # status item, notch, hotkeys, capture wiring
    ├── Models/                      # ScreenshotEntry/Index, CaptureSource, PayloadMode, …
    ├── Services/                    # ScreenshotStore (+Index/+Capture/+Import/+Retention),
    │                                #   CaptureService, Hotkey/DoubleCommandTap, Pasteboard,
    │                                #   QuickLook, Permissions, AppPreferences
    ├── Windows/                     # NotchController (DynamicNotchKit wrapper), NotchGeometry
    └── Views/                       # NotchShelfView, ThumbnailView, DropZoneView, Settings/*
```

The **shots folder is the whole database.** `index.json` is a versioned cache/log
of `{ file, prompt, ts, source }`. On launch and after each change the store
reconciles the index against the PNGs actually on disk.

> **DynamicNotchKit note:** the package's public API can change between major
> versions. All usage is isolated to `Windows/NotchController.swift` — if your
> resolved version differs, that's the only file to adjust.

## Build & run

Requires macOS 14+ and Xcode 16+.

**Xcode (recommended):**
1. `cp BuildSupport/PrivateOverrides.xcconfig.example BuildSupport/PrivateOverrides.xcconfig`
   and set your `DEVELOPMENT_TEAM` (Xcode → Settings → Accounts).
2. Open `IslandNotch.xcodeproj`. Xcode resolves the Swift packages on first open.
3. Select the **IslandNotch** scheme and Run.

**Command line:**
```bash
cd macos
# Optional: regenerate the project from project.yml instead of the committed one
#   brew install xcodegen && xcodegen generate
xcodebuild -project IslandNotch.xcodeproj -scheme IslandNotch \
           -configuration Debug -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/IslandNotch-*/Build/Products/Debug/IslandNotch.app
```

The app launches into the menu bar (no Dock icon). Open **Settings** from the
menu-bar icon.

## Permissions

Two one-time system prompts, both handled gracefully (and deep-linked from
**Settings → Permissions**):

- **Screen Recording** — required to capture real pixels. Requested
  automatically on launch; **takes effect only after a full quit + relaunch**
  (`CGPreflightScreenCaptureAccess()` stays cached-false until then).
- **Accessibility** — required **only** for the double-⌘ gesture (the global
  `CGEventTap`). Without it, the keyboard chord still works.

### ⚠️ Permissions silently break on rebuild unless you sign with a stable identity

This is the single most common "it just stopped working" bug, so read this.

**Symptom:** double-tap ⌘ stops triggering screenshots (no crosshair), and/or
captures come out blank — even though **System Settings still shows IslandNotch
toggled ON** for Accessibility / Screen Recording. It usually starts right after
a rebuild (`bun run dev`, an Xcode build, etc.).

**Root cause:** macOS TCC ties each permission grant to the app's **code-signing
identity**. With **no `DEVELOPMENT_TEAM` set, the build is ad-hoc signed**
(`Signature=adhoc`), and an ad-hoc signature's identity is its **cdhash** — which
changes on *every* build. So each rebuild produces a binary TCC treats as a
brand-new app: the old grant no longer matches, `AXIsProcessTrusted()` /
`CGPreflightScreenCaptureAccess()` return false, and the ⌘ tap never installs.
The Settings toggle still *looks* on because it points at the now-stale binary.

**Automatic fix (local dev):** `bun run dev` / `scripts/build-island-notch.sh`
auto-provisions a stable **Constellagent IslandNotch Dev** certificate in
`macos/.build/signing/` and re-signs the app after every build. Grants only
need to be granted **once** for that certificate (unless you had stale ad-hoc
grants — see reset commands below).

The build script imports the cert + private key as a PKCS#12 bundle into a
dedicated keychain (`macos/.build/signing/islandnotch-dev.keychain-db`) and
signs by **certificate name** (`Constellagent IslandNotch Dev`), not by SHA-1
hash. Self-signed dev certs often show `0 valid identities found` in
`security find-identity` but still codesign correctly by name.

**Build fails with `no identity found` during re-signing.** If
`scripts/build-island-notch.sh` prints:

```text
[island-notch] re-signing with stable dev certificate (TCC grants survive rebuilds)
958BDF46119732148D99167F37CB4BCDEE76D60F: no identity found
```

the keychain has the certificate but not a usable private-key identity (usually
from a stale `macos/.build/signing/` tree created before PKCS#12 import was
fixed). Reset local signing artifacts and rebuild:

```bash
rm -rf macos/.build/signing
CONSTELLAGENT_ISLAND_NOTCH_NO_LAUNCH=1 sh scripts/build-island-notch.sh
# expect: [island-notch] signed: Constellagent IslandNotch Dev
```

If permissions still misbehave after that, reset stale TCC grants once (commands
below) and re-grant in System Settings.

**Manual fix (Apple Development team):** sign with your Apple Developer Team ID
so grants persist the same way:

```bash
cp macos/BuildSupport/PrivateOverrides.xcconfig.example \
   macos/BuildSupport/PrivateOverrides.xcconfig
# then set your team in that (gitignored) file:
#   DEVELOPMENT_TEAM = ABCDE12345      # Xcode → Settings → Accounts, or the
#                                      # OU= field of `security find-identity -v -p codesigning`
```

Rebuild, then confirm the signature is no longer ad-hoc:

```bash
codesign -dvv .../Build/Products/Debug/IslandNotch.app 2>&1 | grep -E 'Signature|TeamIdentifier'
# want:  Authority=Apple Development: …   /   TeamIdentifier=ABCDE12345
# (the build script also prints a loud ⚠️ warning whenever it produces an ad-hoc build)
```

**Clearing a stale grant.** If you'd already granted the ad-hoc build, a dead
entry lingers in the TCC list and the freshly-signed binary won't match it. Reset
it once, then re-grant against the stable identity:

```bash
tccutil reset Accessibility com.constellagent.islandnotch
tccutil reset ScreenCapture  com.constellagent.islandnotch
# relaunch; grant each prompt once; Screen Recording needs one more quit+relaunch.
```

**Verifying live** (watch the app report its own permission state):

```bash
log stream --predicate 'subsystem == "com.constellagent.islandnotch"' --level debug --style compact
#  …[permissions] refresh ax=true screen=true   ← both granted
#  …[hotkey] double-⌘ tap installed             ← the CGEventTap is active
#  …[hotkey] double-⌘ fireCapture               ← a gesture was recognized
```

## Distribution

Distribute as a Developer-ID **notarized**, **non-sandboxed** app. The App
Sandbox is impractical here (global event tap, launching `/usr/sbin/screencapture`,
writing to `~/Desktop`). Hardened Runtime is enabled (`ENABLE_HARDENED_RUNTIME`),
which is required for notarization; no hardened-runtime exceptions are needed.

## Settings reference

| Tab | Controls |
|-----|----------|
| General | Shots folder (Desktop vs Application Support), retention sweep, per-source auto-copy |
| Agents | Active agent, per-agent clipboard payload mode, custom agent name |
| Hotkey | Capture chord recorder, double-⌘ toggle |
| Permissions | Live Screen Recording / Accessibility status + prompts & deep links |
