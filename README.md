# Spruce Notch

Spruce Notch turns your MacBook notch into a live, interactive utility space for media, system controls, quick sharing, and more.

## Features

- Live media controls with visualizer and playback actions
- Calendar and reminder integrations
- Shelf for temporary file holding, previewing, and sharing
- System HUD replacements for volume, brightness, and keyboard backlight
- Webcam/mirror and additional notch-driven live activities

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel Mac
- Xcode 16+ (for local builds)

## Install

### Download DMG

Download the latest release from GitHub, then move `Spruce Notch.app` into `/Applications`.

```bash
xattr -dr com.apple.quarantine /Applications/spruceNotch.app
```

Run the command once if macOS blocks first launch due to unidentified developer warnings.

### Homebrew

```bash
brew install --cask TheBoredTeam/spruce-notch/spruce-notch
```

## Build From Source

```bash
git clone https://github.com/TheBoredTeam/spruce.notch.git
cd spruce.notch
open spruceNotch.xcodeproj
```

Build and run with `Cmd + R` in Xcode.

## Usage

- Launch the app and hover over the notch to expand it
- Use the notch UI for media and live activity controls
- Use the menu bar icon to configure behavior and layout

## Contributing

See `CONTRIBUTING.md` for contribution flow, conventions, and local setup notes.

## Security

Please report vulnerabilities through the process in `SECURITY.md`.

## Acknowledgments

Spruce Notch is built on top of great open-source work, including:

- [MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)
- [NotchDrop](https://github.com/Lakr233/NotchDrop)

See `THIRD_PARTY_LICENSES` for full attribution details.
