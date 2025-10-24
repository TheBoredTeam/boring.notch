<h1 align="center">
  <br>
  <a href="http://thebored.name"><img src="https://framerusercontent.com/images/RFK4vs0kn8pRMuOO58JeyoemXA.png?scale-down-to=256" alt="Boring Notch" width="150"></a>
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

> **⚠️ This is a personal fork with experimental features**
>
> This repository is based on the amazing work by [TheBoredTeam](https://github.com/TheBoredTeam/boring.notch). All credit for the original Boring Notch application goes to them.
>
> **Custom Features Added in This Fork:**
> 1. **Real-time Scrolling Lyrics** - Live synchronized lyrics display in the notch area with automatic timing
> 2. **Multiple Lyrics Display Modes:**
>    - **Flowing Mode** - Current line on left, next line on right (classic side-by-side)
>    - **Alternating Mode** - Lyrics alternate between left and right sides as they progress
>    - **Stacked Mode** - Adaptive layout:
>      - On displays WITH notch: 2x2 grid showing 4 lines (current + next highlighted, upcoming + further dimmed)
>      - On displays WITHOUT notch: Centered vertical stack with 2 lines
> 3. **Per-Display Lyrics Configuration** - Set independent lyrics modes for each connected monitor
> 4. **Automatic Display Detection** - Detects notch presence and adapts layout automatically
> 5. **User-Configurable Lyrics Timing Offset** - Fine-tune lyrics synchronization with +/- time adjustments
> 6. **Enhanced Lyrics UI** - Gradient effects, improved typography, seamless notch extension design
> 7. **Fixed Hover Detection** - Proper hover behavior for notch opening when lyrics mode is active
> 8. **Improved Music Playback Tracking** - Better song change detection and state management
>
> These features are experimental and developed for personal use. For the official, stable version, please visit the [original repository](https://github.com/TheBoredTeam/boring.notch).

### 📸 Custom Features Screenshots

#### Per-Display Lyrics Configuration
<img width="696" alt="Per-Display Settings" src="https://github.com/user-attachments/assets/38a52830-6a5f-41d0-8e82-68c49433c0c9" />

#### Lyrics Display Modes in Action
<img width="1798" alt="Lyrics Modes Overview" src="https://github.com/user-attachments/assets/8e4b0c53-4f18-48bb-8efd-563f28ef3c37" />

#### Flowing Mode (Side-by-Side)
<img width="1172" alt="Flowing Mode Lyrics" src="https://github.com/user-attachments/assets/85fe4288-95c4-4318-b574-422c9d6be11e" />

#### Alternating Mode
<img width="1468" alt="Alternating Mode Lyrics" src="https://github.com/user-attachments/assets/90f03f50-0e09-46e1-8f35-b4c8bb8aab52" />

#### Stacked Mode Grid Layout (2x2 on Notch Display)
<img width="662" alt="Stacked Mode Grid" src="https://github.com/user-attachments/assets/4c73ffb1-91b5-4e47-be80-2a6ff48a5018" />

#### Lyrics Feature Demo
https://github.com/user-attachments/assets/f99843f4-af1d-4944-8359-827181271c9a

---

<!--Welcome to **Boring.Notch**, the coolest way to make your MacBook's notch the star of the show! Forget about those boring status bars—our notch turns into a dynamic music control center, complete with a snazzy visualizer and all the music controls you need. It's like having a mini concert right at the top of your screen! -->

Say hello to **Boring Notch**, the coolest way to make your MacBook's notch the star of the show! Say goodbye to boring status bars: with Boring Notch, your notch transforms into a dynamic music control center, complete with a vibrant visualizer and all the essential music controls you need. But that's just the start! Boring Notch also offers calendar integration, a handy file shelf with AirDrop support and more!

<p align="center">
  <img src="https://github.com/user-attachments/assets/2d5f69c1-6e7b-4bc2-a6f1-bb9e27cf88a8" alt="Demo GIF" />
</p>

<!--https://github.com/user-attachments/assets/19b87973-4b3a-4853-b532-7e82d1d6b040-->
---
<!--## Table of Contents
- [Installation](#installation)
- [Usage](#usage)
- [Roadmap](#-roadmap)
- [Building from Source](#building-from-source)
- [Contributing](#-contributing)
- [Join our Discord Server](#join-our-discord-server)
- [Star History](#star-history)
- [Buy us a coffee!](#buy-us-a-coffee)
- [Acknowledgments](#-acknowledgments)-->

## Installation

**System Requirements:**  
- macOS **14 Sonoma** or later  
- Apple Silicon or Intel Mac

---
> [!IMPORTANT]
> We don't have an Apple Developer account yet. The application will show a popup on first launch that the app is from an unidentified developer.
> 1. Click **OK** to close the popup.
> 2. Open **System Settings** > **Privacy & Security**.
> 3. Scroll down and click **Open Anyway** next to the warning about the app.
> 4. Confirm your choice if prompted.
>
> You only need to do this once.


### Option 1: Download and Install Manually
<a href="https://github.com/TheBoredTeam/boring.notch/releases/latest/download/boringNotch.dmg" target="_self"><img width="200" src="https://github.com/user-attachments/assets/e3179be1-8416-4b8a-b417-743e1ecc67d6" alt="Download for macOS" /></a>

---

### Option 2: Install via Homebrew

You can also install the app using [Homebrew](https://brew.sh):

```bash
brew install --cask TheBoredTeam/boring-notch/boring-notch --no-quarantine
```

## Usage

- Launch the app, and voilà—your notch is now the coolest part of your screen.
- Hover over the notch to see it expand and reveal all its secrets.
- Use the controls to manage your music like a rockstar.

## 📋 Roadmap
- [x] Playback live activity 🎧
- [x] Calendar integration 📆
- [x] Mirror 📷
- [x] Charging indicator and current percentage 🔋
- [x] Customizable gesture control 👆🏻
- [x] Shelf functionality with AirDrop 📚
- [x] Notch sizing customization, finetuning on different display sizes 🖥️
- [ ] Reminders integration ☑️
- [ ] Customizable Layout options 🛠️
- [ ] Extension system 🧩
- [ ] System HUD replacements (volume, brightness, backlight) 🎚️💡⌨️
- [ ] Notifications (under consideration) 🔔
<!-- - [ ] Clipboard history manager 📌 `Extension` -->
<!-- - [ ] Download indicator of different browsers (Safari, Chromium browsers, Firefox) 🌍 `Extension`-->
<!-- - [ ] Customizable function buttons 🎛️ -->
<!-- - [ ] App switcher 🪄 -->

<!-- ## 🧩 Extensions
> [!NOTE]
> We’re hard at work on some awesome extensions! Stay tuned, and we’ll keep you updated as soon as they’re released. -->

## Building from Source

### Prerequisites

- **macOS 14 or later**: If you’re not on the latest macOS, we might need to send a search party.
- **Xcode 16 or later**: This is where the magic happens, so make sure it’s up-to-date.

### Installation

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/TheBoredTeam/boring.notch.git
   cd boring.notch
   ```

2. **Open the Project in Xcode**:
   ```bash
   open boringNotch.xcodeproj
   ```

3. **Build and Run**:
    - Click the "Run" button or press `Cmd + R`. Watch the magic unfold!

## 🤝 Contributing

We’re all about good vibes and awesome contributions! Here’s how you can join the fun:

1. **Fork the Repo**: Click that shiny "Fork" button and make your own version.
2. **Clone Your Fork**:
   ```bash
   git clone https://github.com/{your-name}/boring.notch.git
   # Replace {your-name} with your GitHub username
   ```
3. **Make sure to use `dev` branch as base.**
4. **Create a New Branch**:
   ```bash
   git checkout -b feature/{your-feature-name}
   # Replace {your-feature-name} with a descriptive and concise name for your branch
   # It is best practice to use only alphanumeric characters, write words in lowercase
   # and seperate words with a single hyphen
   ```
5. **Make Your Changes**: Add that feature or fix that bug.
6. **Commit Your Changes**:
   ```bash
   git commit -m "insert descriptive message here"
   ```
7. **Push to Your Fork**:
   ```bash
   git push origin feature/{your-feature-name}
   # Remember to replace {your-feature-name} with the name you chose
   ```
8. **Create a Pull Request**: Head to the original repository and click on "New Pull Request." Fill in the required details, **make sure the base branch is set to `dev`**, and submit your PR. Let’s see what you’ve got!

## Join our Discord Server

<a href="https://discord.gg/GvYcYpAKTu" target="_blank"><img src="https://iili.io/28m3GHv.png" alt="Join The Boring Server!" style="height: 60px !important;width: 217px !important;" ></a>

## Star History

<a href="https://www.star-history.com/#TheBoredTeam/boring.notch&Timeline">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=TheBoredTeam/boring.notch&type=Timeline&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=TheBoredTeam/boring.notch&type=Timeline" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=TheBoredTeam/boring.notch&type=Timeline" />
 </picture>
</a>

## Buy us a coffee!

<a href="https://www.buymeacoffee.com/jfxh67wvfxq" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-red.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

## 🎉 Acknowledgments

We would like to express our appreciation to the developers of [NotchDrop](https://github.com/Lakr233/NotchDrop), an open-source project that has been instrumental in developing the "Shelf" feature in Boring Notch. Special thanks to Lakr233 for their contributions to NotchDrop and to [Hugo Persson](https://github.com/Hugo-Persson) for integrating it into our project.

### Icon credits: [@maxtron95](https://github.com/maxtron95)
### Website credits: [@himanshhhhuv](https://github.com/himanshhhhuv)

- **SwiftUI**: For making us look like coding wizards.
- **You**: For being awesome and checking out **boring.notch**!


