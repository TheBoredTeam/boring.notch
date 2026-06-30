<h1 align="center">
  <br>
  <a href="https://www.minitap.ai"><img src="https://www.minitap.ai/_next/image?url=%2Fbrand%2Fminitap-logo.png&w=3840&q=75" alt="minitap" width="260"></a>
  <br>
  minitap
  <br>
</h1>

minitap turns the MacBook notch into a compact control surface for media, calendar context, file handoff, clipboard history, system HUDs, focus tools, and quick visual checks.
It uses the minitap identity across the app: light surfaces, purple accent controls, Archivo UI typography, Clash Display headings, and a bundled minitap app icon.

## Requirements

- macOS 14 Sonoma or later.
- Apple Silicon or Intel Mac.
- Xcode 16 or later for local development.

## Install

Open the release DMG, then move `minitap.app` to `/Applications`.

If macOS shows an unidentified developer warning, remove the quarantine flag after moving the app:

```bash
xattr -dr com.apple.quarantine /Applications/minitap.app
```

Then open minitap normally.

## Use

- Launch minitap.
- Hover over the notch to expand the surface.
- Use media controls, calendar context, Shelf, clipboard history, mirror, battery state, and HUD replacement features from the notch.
- Open the menu bar item to configure behavior, appearance, media controls, permissions, and advanced options.

## Build

Clone this repository, open the Xcode project, then build the app target:

```bash
open boringNotch.xcodeproj
```

The built app product is `minitap.app`.
The app bundle identifier is `ai.minitap.minitap`.
The XPC helper bundle identifier is `ai.minitap.minitap.MinitapXPCHelper`.
The Spotify callback URL scheme is `minitap://spotify-auth/callback`.

## Package

The DMG wrapper expects the renamed app bundle:

```bash
Configuration/dmg/create_dmg.sh /path/to/minitap.app /path/to/minitap.dmg minitap
```

The Sparkle feed URL is configured as `https://www.minitap.ai/appcast.xml`.
Host a signed appcast at that URL before shipping updater-enabled builds.

## Contribute

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
Keep user-facing copy, bundle identifiers, URL schemes, and app assets aligned with the minitap brand contract in `boringNotch/models/MinitapBrand.swift`.

## Acknowledgments

minitap builds on SwiftUI, Sparkle, LaunchAtLogin, Defaults, KeyboardShortcuts, Lottie, AsyncXPCConnection, MacroVisionKit, MediaRemoteAdapter, and related open-source work.
See [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) for attribution details.
