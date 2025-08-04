# Boring Notch
<!--Welcome to **Boring.Notch**, the coolest way to make your MacBook's notch the star of the show! Forget about those boring status bars—our notch turns into a dynamic music control center, complete with a snazzy visualizer and all the music controls you need. It's like having a mini concert right at the top of your screen! -->

Say hello to **Boring Notch**, the coolest way to make your MacBook’s notch the star of the show! Say goodbye to boring status bars: with Boring Notch, your notch transforms into a dynamic music control center, complete with a vibrant visualizer and all the essential music controls you need. But that’s just the start! Boring Notch also offers calendar integration, a handy file shelf with AirDrop support and more!

![Preview](https://github.com/user-attachments/assets/722f1536-e5a1-45d5-b905-86447666b771)


<!--![Boring Notch Build & Test](https://github.com/TheBoredTeam/boring.notch/actions/workflows/cicd.yml/badge.svg)-->


<!--https://github.com/user-attachments/assets/19b87973-4b3a-4853-b532-7e82d1d6b040-->

## Table of Contents
- [Roadmap](#-roadmap)
- [Extensions](#-extensions)
- [Installation](#installation)
- [Usage](#usage)
- [Building from Source](#building-from-source)
- [Contributing](#-contributing)
- [Join our Discord Server](#join-our-discord-server)
- [Star History](#star-history)
- [Buy us a coffee!](#buy-us-a-coffee)
- [License](#-license)
- [Acknowledgments](#-acknowledgments)

## 📋 Roadmap
- [x] Playback live activity 🎧
- [x] Calendar integration 📆
- [x] Mirror 📷
- [x] Charging indicator and current percentage 🔋
- [x] Customizable gesture control 👆🏻
- [x] Shelf functionality with AirDrop 📚
- [x] Notch sizing customization, finetuning on different display sizes 🖥️
- [ ] Layout options 🛠️
- [ ] Extension system 🧩
- [ ] Clipboard history manager 📌 `Extension`
- [ ] System HUD replacements (volume, brightness, backlight) 🎚️💡⌨️ `Extension`
- [ ] Download indicator of different browsers (Safari, Chromium browsers, Firefox) 🌍 `Extension`
- [ ] Customizable function buttons 🎛️
- [ ] App switcher 🪄
- [ ] Notifications (under consideration) 🔔

## 🧩 Extensions
> [!NOTE]
> We’re hard at work on some awesome extensions! Stay tuned, and we’ll keep you updated as soon as they’re released.

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
<a href="https://github.com/TheBoredTeam/boring.notch/releases/latest/download/Flying_Rabbit.dmg" target="_self"><img width="200" src="https://github.com/user-attachments/assets/e3179be1-8416-4b8a-b417-743e1ecc67d6" alt="Download for macOS" /></a>

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

### Icon credits: [@maxtron95](https://github.com/maxtron95)
### Website credits: [@himanshhhhuv](https://github.com/himanshhhhuv)

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

[![Star History Chart](https://api.star-history.com/svg?repos=TheBoredTeam/boring.notch&type=Timeline)](https://star-history.com/#TheBoredTeam/boring.notch&Timeline)

## Buy us a coffee!

<a href="https://www.buymeacoffee.com/jfxh67wvfxq" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-red.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>


## 📝 License

This project is licensed under the GNU General Public License v3.0.
See the THIRD_PARTY_LICENSES file for details on licenses of third-party dependencies.


## 🎉 Acknowledgments

We would like to express our appreciation to the developers of [NotchDrop](https://github.com/Lakr233/NotchDrop), an open-source project that has been instrumental in developing the "Shelf" feature in Boring Notch. Special thanks to Lakr233 for their contributions to NotchDrop and to [Hugo Persson](https://github.com/Hugo-Persson) for integrating it into our project.

- **SwiftUI**: For making us look like coding wizards.
- **You**: For being awesome and checking out **boring.notch**!


