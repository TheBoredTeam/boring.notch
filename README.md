# Boring Notch (Fork)

<p align="center">
  <a href="http://theboring.name"><img src="https://framerusercontent.com/images/RFK4vs0kn8pRMuOO58JeyoemXA.png?scale-down-to=256" alt="Boring Notch" width="150"></a>
  <br>
  Boring Notch
  <br>
  <sub><em>Built on <a href="https://github.com/TheBoredTeam/boring.notch">TheBoredTeam/boring.notch</a></em></sub>
</h1>

<p align="center">
  <a href="https://discord.gg/c8JXA7qrPm">
    <img src="https://dcbadge.limes.pink/api/server/https://discord.gg/c8JXA7qrPm?style=flat" alt="Discord Badge" />
  </a>
</p>

---

## About This Fork

This is a modified version of [Boring Notch](https://github.com/TheBoredTeam/boring.notch) by [TheBoredTeam](https://github.com/TheBoredTeam). 

Boring Notch transforms your MacBook's notch into a dynamic HUD with music controls, calendar integration, shelf functionality, and more. This fork builds upon the original with additional features listed below.

### Original Features
- Music playback live activity with visualizer
- Calendar integration
- Shelf functionality with AirDrop
- Charging indicator and battery percentage
- System HUD replacements (volume, brightness, backlight)
- Customizable gesture control

### Added Features (This Fork)
- 🎭 **Face Animations** – Animated faces that display in the notch when inactive (6 types: Minimal, Cool, Surprised, Sleepy, Wink, Happy)
- 🍅 **Pomodoro Timer** – Built-in pomodoro timer with customizable work/break durations and session tracking
- ⏱️ **Timer Display** – Live countdown display in closed notch when timer is running
- 🔊 **Music Visualizer** – Enhanced audio spectrum visualizer in the notch

---

## Installation

**System Requirements:**
- macOS **14 Sonoma** or later
- Apple Silicon or Intel Mac

### Download

<a href="https://github.com/christianteohx/boring.notch/releases/latest/download/boringNotch.dmg" target="_self"><img width="200" src="https://github.com/user-attachments/assets/e3179be1-8416-4b8a-b417-743e1ecc67d6" alt="Download for macOS" /></a>

Once downloaded, open the `.dmg` and move **Boring Notch** to your `/Applications` folder.

> [!IMPORTANT]
> Since this is a forked app with ad-hoc code signing, macOS may warn you that it's from an unidentified developer.
>
> After moving to Applications, run:
> ```bash
> xattr -dr com.apple.quarantine /Applications/boringNotch.app
> ```

---

## Building from Source

### Prerequisites

- **macOS 14 or later**
- **Xcode 16 or later**

### Installation

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/christianteohx/boring.notch.git
   cd boring.notch
   ```

2. **Open the Project in Xcode**:
   ```bash
   open boringNotch.xcodeproj
   ```

3. **Build and Run**:
   - Click the "Run" button or press `Cmd + R`

---

## Features

### Face Animations
Choose from 6 animated face types:
- **Minimal** – Simple face with blinking eyes
- **Cool** – Sunglasses with smirk animation
- **Surprised** – Wide eyes with "O" mouth
- **Sleepy** – Half-closed eyes
- **Wink** – Periodic eye wink
- **Happy** – Curved ^_^ eyes with bounce

Face animations can run in Fixed mode (one face) or Random mode (cycles through faces).

### Pomodoro Timer
- Customizable work duration (1-90 minutes)
- Short break duration (1-30 minutes)
- Long break duration (1-60 minutes)
- Session counter (resets after N sessions)
- Live countdown display in the notch

### Music Visualizer
Audio spectrum visualizer with animated bars that react to audio playback.

---

## Credits

- **Original Project**: [Boring Notch](https://github.com/TheBoredTeam/boring.notch) by [TheBoredTeam](https://github.com/TheBoredTeam)
- **SwiftUI**: For making us look like coding wizards

For a full list of licenses and attributions, see [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md).
