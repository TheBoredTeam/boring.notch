<h1 align="center">
  <br>
  <a href="http://theboring.name"><img src="https://framerusercontent.com/images/RFK4vs0kn8pRMuOO58JeyoemXA.png?scale-down-to=256" alt="Boring Notch" width="150"></a>
  <br>
  Boring Notch
  <br>
</h1>

<p align="center">
  <a title="Crowdin" target="_blank" href="https://crowdin.com/project/boring-notch"><img src="https://badges.crowdin.net/boring-notch/localized.svg"></a>
  <img src="https://github.com/TheBoredTeam/boring.notch/actions/workflows/cicd.yml/badge.svg" alt="TheBoringNotch Build & Test" style="margin-right: 10px;" />
  <a href="https://discord.gg/c8JXA7qrPm">
    <img src="https://dcbadge.limes.pink/api/server/https://discord.gg/c8JXA7qrPm?style=flat" alt="Discord Badge" />
  </a>
</p>

Say hello to **Boring Notch**! We're transforming your MacBook’s static hardware notch into an interactive, dynamic control center. Say goodbye to dead space and status bars—with Boring Notch, your top screen transforms into a beautifully tailored Live Activity hub.

<p align="center">
  <img src="https://github.com/user-attachments/assets/2d5f69c1-6e7b-4bc2-a6f1-bb9e27cf88a8" alt="Demo GIF" />
</p>

## ✨ What's New
We recently supercharged the Notch functionality to make it even more essential to your daily workflow:

- 📝 **Quick Notes:** Unveil a sleek, glassmorphism-styled persistent text editor hidden right inside the notch. Perfect for fleeting thoughts, with one-click copy and clear operations!
- 🍅 **Dual-Status Pomodoro:** Track your focus timer and your currently playing music *at the exact same time*. Watch your countdown tick natively inside the idle hardware notch without sacrificing your current window layout.
- 📐 **Strict Hardware Confinement:** We rebuilt the underlying SwiftUI bounds! Battery, Music, and Timer background animations now perfectly conform to the strict dimensions of the physical Mac notch when not actively hovered, explicitly preventing awkward horizontal software stretching out of nothing.


## 🚀 Features at a Glance

- **Now Playing Media Controls:** Manage your music like a rockstar, complete with a vibrant live spectrum visualizer.
- **Calendar & Reminders:** Instantly check your upcoming events or clear tasks.
- **Quick Notes & Pomodoro:** Ultimate productivity tools always just a hover away.
- **MacOS System HUDs:** Clean inline indicators for volume, brightness, battery percentage, and charging states.
- **Shelf & AirDrop:** Drag and drop files onto the notch to hide them or instantly AirDrop them.

---

## 🛠️ Installation

**System Requirements:**
- macOS **14 Sonoma** or later
- Apple Silicon or Intel Mac

### Option 1: Download & Install (Recommended)

1. Download the latest release `.dmg` from the **[Releases Tab](../../releases/latest)**.
2. Open the `.dmg` and drag **Boring Notch** into your `/Applications` folder.

> [!IMPORTANT]
> Because this is a free, independent open-source project, macOS Gatekeeper will warn you that the app is from an "unidentified developer" or claim it is damaged on first launch. 
> **To fix this quickly:**
> Open your **Terminal** app and paste this exact command to remove Apple's quarantine:
> ```bash
> xattr -cr /Applications/boringNotch.app
> ```

### Option 2: Install via Homebrew
Installing via Homebrew automatically skips the Apple Quarantine warning!
```bash
brew install --cask TheBoredTeam/boring-notch/boring-notch
```

---

## 💻 Building from Source

We welcome all developers who want to tinker with the Notch's behavior or design new widgets!

**Prerequisites:**
- **Xcode 16+**
- **macOS 14+**

```bash
# 1. Clone the Repository
git clone https://github.com/TheBoredTeam/boring.notch.git
cd boring.notch

# 2. Open the Project
open boringNotch.xcodeproj

# 3. Build & Run
# Select "boringNotch" target and press Cmd + R.
```

## 🤝 Contributing

We’re all about good vibes and awesome contributions! Read [CONTRIBUTING.md](CONTRIBUTING.md) to learn how you can build new modular features or widgets for the Notch. Whether you're fixing a bug, adding new Live Activities, or creating UI Polish, we want your PRs!


## 💖 Support the Team

<a href="https://www.ko-fi.com/alexander5015" target="_blank"><img src="https://github.com/user-attachments/assets//a76175ef-7e93-475a-8b67-4922ba5964c2" alt="Support us on Ko-fi" style="height: 70px; width: 346px;" ></a>

### Notable Open Source Credits
- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)** – Using the Now Playing source in macOS 15.4+
- **[NotchDrop](https://github.com/Lakr233/NotchDrop)** – Instrumental in building the File Shelf feature.
- See the [Third-Party Licenses](./THIRD_PARTY_LICENSES.md) for full attributions.

---
*Built with Swift, SwiftUI, and love.*
