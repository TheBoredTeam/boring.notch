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
  <a href="https://www.ko-fi.com/alexander5015">
    <img src="https://srv-cdn.himpfen.io/badges/kofi/kofi-flat.svg" alt="Ko-Fi" />
  </a>
</p>

<!--Welcome to **Boring.Notch**, the coolest way to make your MacBook's notch the star of the show! Forget about those boring status bars—our notch turns into a dynamic music control center, complete with a snazzy visualizer and all the music controls you need. It's like having a mini concert right at the top of your screen! -->

Say hello to **Boring Notch**, the coolest way to make your MacBook’s notch the star of the show! Say goodbye to boring status bars: with Boring Notch, your notch transforms into a dynamic music control center, complete with a vibrant visualizer and all the essential music controls you need. But that’s just the start! Boring Notch also offers calendar integration, a handy file shelf with AirDrop support, a complete MacOS HUD replacement and more!

<p align="center">
  <img src="https://github.com/user-attachments/assets/2d5f69c1-6e7b-4bc2-a6f1-bb9e27cf88a8" alt="Demo GIF" />
</p>

## <!--https://github.com/user-attachments/assets/19b87973-4b3a-4853-b532-7e82d1d6b040-->

## 🍴 About This Fork

> This is a personal fork of [**TheBoredTeam/boring.notch**](https://github.com/TheBoredTeam/boring.notch), maintained by [**@maksiosmf**](https://github.com/maksiosmf), adding a set of extra widgets and quality-of-life features on top of the original.
>
> 🔗 **Fork:** [`github.com/maksiosmf/boring.notch`](https://github.com/maksiosmf/boring.notch) &nbsp;·&nbsp; ⬆️ **Upstream:** [`TheBoredTeam/boring.notch`](https://github.com/TheBoredTeam/boring.notch)

### ✨ What's new in this fork

|     | Feature                          | Description                                                                                                |
| :-: | :------------------------------- | :--------------------------------------------------------------------------------------------------------- |
| 🎧  | **Bluetooth / AirPods popup**    | iOS-style "device connected" pill on the notch, with battery level (AirPods, mouse, keyboard, headphones). |
| 🔋  | **iOS-style charging animation** | Pulsing bolt + percentage when you plug in the charger.                                                    |
| 🔊  | **Audio output switcher**        | Switch the system output device (AirPods / speakers / HDMI) right from the open notch.                     |
| 🌡️  | **System monitor**               | Live CPU, memory, disk and network usage — plus **real CPU temperature**.                                  |
| ⛅  | **Weather widget**               | Current weather via [wttr.in](https://wttr.in) (no API key) — auto-located by IP or a city of your choice. |
| 🏠  | **Customizable Home**            | Pick small components (clock, weather, CPU temp, CPU / RAM / disk) to show on the Home tab.                |
| 📐  | **Adaptive notch height**        | The open notch grows downward to fit widgets instead of squishing them.                                    |
| ⚡  | **Snappier battery popups**      | Plug / unplug indicators appear instantly.                                                                 |
| 🛠️  | **Helper build fix**             | Restored the XPC helper compilation so Accessibility / HUD replacement work again.                         |

Everything new lives under **Settings → Home** and **Settings → Widgets**.

### 📁 Modified files

A full list of what this fork touches relative to upstream — useful if you'd like to cherry-pick any of it.

<details>
<summary><b>New files (13)</b></summary>

| File | What it does |
| :--- | :--- |
| `boringNotch/managers/BluetoothActivityManager.swift` | Watches IOBluetooth connect/disconnect notifications, reads device battery level, debounces duplicate events and skips nameless devices, then triggers the notch popup. |
| `boringNotch/components/Live activities/BoringBluetoothPopup.swift` | The iOS-style "device connected" pill shown on the closed notch (device icon, name, battery). |
| `boringNotch/components/Live activities/BoringChargingAnimation.swift` | iOS-style charging popup: pulsing bolt, battery percentage and time-to-full on the closed notch. |
| `boringNotch/managers/AudioDeviceManager.swift` | CoreAudio wrapper: lists output devices, observes default-device changes, switches the system output device. |
| `boringNotch/components/Notch/AudioDeviceMenu.swift` | Speaker menu in the open-notch header for picking the output device. |
| `boringNotch/managers/SystemMonitorManager.swift` | Samples CPU, RAM, disk and network usage on a configurable interval (Mach host APIs + `getifaddrs`). |
| `boringNotch/managers/CPUTemperatureReader.swift` | In-process CPU temperature via private IOHID thermal-sensor APIs resolved with `dlsym` (averages on-die sensors). |
| `boringNotch/components/Notch/SystemMonitorView.swift` | The system-monitor widget UI (CPU / RAM / disk / network / temperature rows). |
| `boringNotch/managers/WeatherManager.swift` | Fetches current weather from [wttr.in](https://wttr.in) (no API key), with manual-city support and a configurable refresh interval. |
| `boringNotch/managers/LocationManager.swift` | IP-based auto-location (city lookup) for the weather widget. |
| `boringNotch/components/Notch/WeatherWidgetView.swift` | The weather widget UI (condition icon, temperature, city). |
| `boringNotch/components/Notch/WidgetsView.swift` | The new **Widgets** tab hosting the system monitor and weather widgets. |
| `boringNotch/components/Notch/HomeWidgetsView.swift` | Row of small, individually-toggleable components (clock, weather, CPU temp, CPU / RAM / disk) under the music player on the Home tab. |

</details>

<details>
<summary><b>Modified files (19)</b></summary>

| File | What changed |
| :--- | :--- |
| `boringNotch/models/Constants.swift` | New `Defaults` keys for all fork features (charging animation, audio switcher, Bluetooth popup, system monitor, weather, Home components) + `WeatherUnit` enum. |
| `boringNotch/components/Settings/SettingsView.swift` | New settings UI: Home-tab component toggles and a **Widgets** section (system monitor, weather, Bluetooth popup, charging animation, audio switcher). |
| `boringNotch/ContentView.swift` | Renders the new closed-notch popups (charging, Bluetooth), routes the new `.widgets` tab, and adds adaptive open-notch height (`openNotchContentHeight`) so the notch grows downward for widget content instead of squishing it. |
| `boringNotch/BoringViewCoordinator.swift` | New `SneakContentType` cases (`.bluetooth`, `.charging`, `.audioDevice`) and per-type popup durations (4 s for Bluetooth/charging). |
| `boringNotch/enums/generic.swift` | Adds `.widgets` to `NotchViews`. |
| `boringNotch/components/Tabs/TabSelectionView.swift` | Adds the **Widgets** tab; tabs are now filtered by settings (Shelf hidden when disabled, Widgets shown only when a widget is enabled). |
| `boringNotch/components/Notch/BoringHeader.swift` | Shows tabs when the Widgets tab is enabled (even without Shelf) and adds the audio-device menu button. |
| `boringNotch/components/Notch/NotchHomeView.swift` | Wraps the Home layout in a `VStack` and appends `HomeWidgetsView` when any Home component is enabled. |
| `boringNotch/sizing/matters.swift` | Replaces fixed `openNotchSize` height with `openNotchBaseHeight` (190) + `openNotchMaxHeight` (235); the window is created at max height and the visible shape scales to content. |
| `boringNotch/models/BatteryStatusViewModel.swift` | Sends `.charging` (instead of `.battery`) popups when the iOS charging animation is enabled. |
| `boringNotch/managers/BatteryActivityManager.swift` | Reduces battery-event queue spacing from 1 s to 0.05 s so plug/unplug popups appear instantly. |
| `boringNotch/boringNotchApp.swift` | Starts `BluetoothActivityManager` on launch. |
| `BoringNotchXPCHelper/BoringNotchXPCHelper.swift` | Adds an IOHID-based CPU-temperature reader to the (unsandboxed) helper. |
| `boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift` | New `currentCPUTemperature` XPC method. |
| `boringNotch/XPCHelperClient/XPCHelperClient.swift` | Async client wrapper for the new CPU-temperature XPC call. |
| `boringNotch.xcodeproj/project.pbxproj` | Registers all new files **and fixes the `BoringNotchXPCHelper` target, which had no Sources build phase** — the helper never compiled (empty `.xpc`), so Accessibility / HUD replacement were broken even on upstream. |
| `boringNotch/boringNotch.entitlements` | Disables the App Sandbox (for in-process CPU-temperature reads) and adds Bluetooth + location entitlements. |
| `boringNotch/Info.plist` | Adds location and Bluetooth usage descriptions. |
| `.gitignore` | Ignores `dist/` and `*.dmg`. |

</details>

> [!IMPORTANT]
> **For upstream maintainers:** the `project.pbxproj` fix above (missing Sources build phase on the XPC helper target) likely affects upstream builds too and is independent of the fork features.

> [!NOTE]
> To read CPU temperature sensors, the **App Sandbox is disabled** in this fork. That makes the build a little less locked-down than upstream — perfectly fine for personal use, but worth knowing.

> [!TIP]
> This fork is signed for personal use (no Apple notarization), so on first launch run:
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/boringNotch.app
> ```
>
> then open it normally.

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

### Option 1: Download and Install Manually

<a href="https://github.com/TheBoredTeam/boring.notch/releases/latest/download/boringNotch.dmg" target="_self"><img width="200" src="https://github.com/user-attachments/assets/e3179be1-8416-4b8a-b417-743e1ecc67d6" alt="Download for macOS" /></a>

Once downloaded, open the `.dmg` and move **Boring Notch** to your `/Applications` folder.

> [!IMPORTANT]
> We don't have an Apple Developer account (yet 👀), so macOS will warn you that Boring Notch is from an unidentified developer on first launch. This is expected behavior.
>
> You'll need to bypass this before the app will open. You only need to do this once. Use one of the methods below.

---

#### Recommended: Terminal (Always Works)

This is the quickest and easiest method. It only requires a single command and works consistently for all users. System Settings can sometimes fail and won't work for non-admin users.

After moving Boring Notch to your Applications folder, run:

```bash
xattr -dr com.apple.quarantine /Applications/boringNotch.app
```

Then open the app normally.

---

#### Alternative: System Settings

> [!NOTE]
> This method doesn't work for all users. If this doesn't work, use the Terminal method above.

1. Try to open the app — you'll see a security warning.
2. Click **OK** to dismiss it.
3. Open **System Settings** > **Privacy & Security**.
4. Scroll to the bottom and click **Open Anyway** next to the Boring Notch warning.
5. Confirm if prompted.

---

### Option 2: Install via Homebrew

You can also install using [Homebrew](https://brew.sh). The Homebrew installation automatically bypasses the macOS security warning described above.

```bash
brew install --cask TheBoredTeam/boring-notch/boring-notch
```

## Usage

- Launch the app, and voilà—your notch is now the coolest part of your screen.
- Hover over the notch to see it expand and reveal all its secrets.
- Use the controls to manage your music like a rockstar.
- Click the star in your menu bar to customize your notch to your heart's content.

## 📋 Roadmap

- [x] Playback live activity 🎧
- [x] Calendar integration 📆
- [x] Reminders integration ☑️
- [x] Mirror 📷
- [x] Charging indicator and current percentage 🔋
- [x] Customizable gesture control 👆🏻
- [x] Shelf functionality with AirDrop 📚
- [x] Notch sizing customization, finetuning on different display sizes 🖥️
- [x] System HUD replacements (volume, brightness, backlight) 🎚️💡⌨️
- [x] Bluetooth Live Activity (connect/disconnect for bluetooth devices) — _added in this fork_
- [x] Weather integration ⛅️ — _added in this fork_
- [ ] Customizable Layout options 🛠️
- [ ] Lock Screen Widgets 🔒
- [ ] Extension system 🧩
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

We’re all about good vibes and awesome contributions! Read [CONTRIBUTING.md](CONTRIBUTING.md) to learn how you can join the fun!

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

## Support us on Ko-fi!

<!-- <a href="https://www.buymeacoffee.com/jfxh67wvfxq" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-red.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a> -->

<a href="https://www.ko-fi.com/alexander5015" target="_blank"><img src="https://github.com/user-attachments/assets//a76175ef-7e93-475a-8b67-4922ba5964c2" alt="Support us on Ko-fi" style="height: 70px !important;width: 346px !important;" ></a>

## 🎉 Acknowledgments

We would like to express our gratitude to the authors and maintainers of the open-source projects that made this possible.

## Notable Projects

- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)** – An open-source project that allowed us to use the Now Playing source in macOS 15.4+
- **[NotchDrop](https://github.com/Lakr233/NotchDrop)** – An open-source project that has been instrumental in developing the first version of the "Shelf" feature in Boring Notch.

For a full list of licenses and attributions, please see the [Third-Party Licenses](./THIRD_PARTY_LICENSES.md) file.

### Icon credits: [@maxtron95](https://github.com/maxtron95)

### Website credits: [@himanshhhhuv](https://github.com/himanshhhhuv)

- **SwiftUI**: For making us look like coding wizards.
- **You**: For being awesome and checking out **boring.notch**!
