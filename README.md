<h1 align="center">
  <br>
  Kairo
  <br>
</h1>


<p align="center">
  <img src="https://github.com/wizlox/kairo-notch/actions/workflows/cicd.yml/badge.svg" alt="Kairo Build & Test" style="margin-right: 10px;" />
  <a href="https://discord.gg/c8JXA7qrPm">
    <img src="https://dcbadge.limes.pink/api/server/https://discord.gg/c8JXA7qrPm?style=flat" alt="Discord Badge" />
  </a>
</p>

Say hello to **Kairo**, the coolest way to make your MacBook's notch the star of the show! Say goodbye to boring status bars: with Kairo, your notch transforms into a dynamic music control center, complete with a vibrant visualizer and all the essential music controls you need. But that's just the start! Kairo also offers calendar integration, a handy file shelf with AirDrop support, a complete MacOS HUD replacement and more!

<p align="center">
  <img src="https://github.com/user-attachments/assets/2d5f69c1-6e7b-4bc2-a6f1-bb9e27cf88a8" alt="Demo GIF" />
</p>

---

## Installation

**System Requirements:**
- macOS **14 Sonoma** or later
- Apple Silicon or Intel Mac

---

### Option 1: Download and Install Manually

<a href="https://github.com/wizlox/kairo-notch/releases/latest/download/Kairo.dmg" target="_self"><img width="200" src="https://github.com/user-attachments/assets/e3179be1-8416-4b8a-b417-743e1ecc67d6" alt="Download for macOS" /></a>

Once downloaded, open the `.dmg` and move **Kairo** to your `/Applications` folder.

> [!IMPORTANT]
> We don't have an Apple Developer account (yet), so macOS will warn you that Kairo is from an unidentified developer on first launch. This is expected behavior.
>
> You'll need to bypass this before the app will open. You only need to do this once. Use one of the methods below.

---

#### Recommended: Terminal (Always Works)

This is the quickest and easiest method. It only requires a single command and works consistently for all users. System Settings can sometimes fail and won't work for non-admin users.

After moving Kairo to your Applications folder, run:

```bash
xattr -dr com.apple.quarantine /Applications/Kairo.app
```

Then open the app normally.

---

#### Alternative: System Settings

> [!NOTE]
> This method doesn't work for all users. If this doesn't work, use the Terminal method above.

1. Try to open the app — you'll see a security warning.
2. Click **OK** to dismiss it.
3. Open **System Settings** > **Privacy & Security**.
4. Scroll to the bottom and click **Open Anyway** next to the Kairo warning.
5. Confirm if prompted.

---

### Option 2: Install via Homebrew

You can also install using [Homebrew](https://brew.sh). The Homebrew installation automatically bypasses the macOS security warning described above.

```bash
brew install --cask wizlox/kairo/kairo
```

## Usage

- Launch the app, and voila — your notch is now the coolest part of your screen.
- Hover over the notch to see it expand and reveal all its secrets.
- Use the controls to manage your music like a rockstar.
- Click the star in your menu bar to customize your notch to your heart's content.

## Roadmap
- [x] Playback live activity
- [x] Calendar integration
- [x] Reminders integration
- [x] Mirror
- [x] Charging indicator and current percentage
- [x] Customizable gesture control
- [x] Shelf functionality with AirDrop
- [x] Notch sizing customization, finetuning on different display sizes
- [x] System HUD replacements (volume, brightness, backlight)
- [ ] Bluetooth Live Activity (connect/disconnect for bluetooth devices) 
- [ ] Weather integration
- [ ] Customizable Layout options
- [ ] Lock Screen Widgets
- [ ] Extension system
- [ ] Notifications (under consideration)

## Building from Source

### Prerequisites

- **macOS 14 or later**: If you're not on the latest macOS, we might need to send a search party.
- **Xcode 16 or later**: This is where the magic happens, so make sure it's up-to-date.

### Installation

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/wizlox/kairo-notch.git
   cd kairo-notch
   ```

2. **Open the Project in Xcode**:
   ```bash
   open Kairo.xcodeproj
   ```

3. **Build and Run**:
    - Click the "Run" button or press `Cmd + R`. Watch the magic unfold!

## Contributing

We're all about good vibes and awesome contributions! Read [CONTRIBUTING.md](CONTRIBUTING.md) to learn how you can join the fun!

## Join our Discord Server

<a href="https://discord.gg/GvYcYpAKTu" target="_blank"><img src="https://iili.io/28m3GHv.png" alt="Join the Kairo Discord Server!" style="height: 60px !important;width: 217px !important;" ></a>

## Star History

<a href="https://www.star-history.com/#wizlox/kairo-notch&Timeline">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=wizlox/kairo-notch&type=Timeline&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=wizlox/kairo-notch&type=Timeline" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=wizlox/kairo-notch&type=Timeline" />
 </picture>
</a>

## Acknowledgments

We would like to express our gratitude to the authors and maintainers of the open-source projects that made this possible. 

## Notable Projects
- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)** – An open-source project that allowed us to use the Now Playing source in macOS 15.4+
- **[NotchDrop](https://github.com/Lakr233/NotchDrop)** – An open-source project that has been instrumental in developing the first version of the "Shelf" feature in Kairo.

For a full list of licenses and attributions, please see the [Third-Party Licenses](./THIRD_PARTY_LICENSES.md) file.

- **SwiftUI**: For making us look like coding wizards.
- **You**: For being awesome and checking out **Kairo**!
