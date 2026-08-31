# Changes

This document lists only files added or modified in the current `feature/add-menubar-item-to-nortch` working tree compared with the official [`TheBoredTeam/boring.notch`](https://github.com/TheBoredTeam/boring.notch) `main` branch.



## Reference Note

The following open-source projects were consulted as implementation references:

- **[not-so-boring-notch](https://github.com/Cris2907/not-so-boring-notch)** – Its timer/stopwatch activity and active Bluetooth headphone output event were used as references and adapted to this branch's existing notch and settings architecture.
- **[Ice](https://github.com/jordanbaird/Ice) / [Ice 2](https://github.com/teddychan/ice-2)** – Ice's Window List array fallback was adapted for live previews of offscreen status items, while Ice 2's macOS 26 source-PID handling, three-stage event barrier, and hidden-cursor Command-drag flow were adapted for reliable menu bar item rearrangement.
- **[SaneBar](https://github.com/sane-apps/SaneBar)** – Its human-shaped HID Command-drag sequence was adapted as a fallback when an embedded XPC service cannot complete Ice's per-PID event barrier.
- **[Hidden Bar](https://github.com/dwarvesf/hidden)** – Its widest-display boundary sizing and display-change refresh strategy were adapted for the menu bar hidden section.

## Added Files

### Menu Bar Access

- `BoringNotchXPCHelper/MenuBarEventRelay.swift`
  - Adds the helper-side event relay used by menu bar interactions.
- `BoringNotchXPCHelper/MenuBarItemController.swift`
  - Adds Accessibility-based status item discovery, stable item descriptors, menu snapshots, and menu action execution.
- `boringNotch/components/MenuBarAccess/MenuBarItemsView.swift`
  - Adds the notch item strip, settings UI, live preview capture, fallback icons, ordering, scrolling, and menu presentation.
- `boringNotch/components/MenuBarAccess/MenuBarSystemVisibilityController.swift`
  - Adds the divider status item and expands or collapses the user-arranged hidden menu bar section.

### Timer and Stopwatch

- `boringNotch/components/Time/TimeActivityView.swift`
  - Adds timer and stopwatch setup, active-session controls, and closed-notch presentation.
- `boringNotch/managers/TimeActivityManager.swift`
  - Adds timer and stopwatch lifecycle, pause, resume, reset, completion, and sound handling.
- `boringNotch/models/TimeActivity.swift`
  - Adds timer and stopwatch state models and time formatting.

### Bluetooth Headphone Activity

- `boringNotch/components/Live activities/BluetoothDeviceActivity.swift`
  - Adds the closed-notch Bluetooth headphone connection activity.
- `boringNotch/managers/BluetoothAudioManager.swift`
  - Adds active audio-output and Bluetooth headphone monitoring.
- `boringNotch/models/BluetoothHeadphoneProfile.swift`
  - Adds normalized Bluetooth headphone metadata and matching rules.

## Modified Files

### XPC Helper and Client

- `BoringNotchXPCHelper/BoringNotchXPCHelper.swift`
  - Routes menu bar discovery, menu snapshot, and menu action requests to the new controller.
- `BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift`
  - Adds menu bar request and response models and XPC protocol methods.
- `BoringNotchXPCHelper/main.swift`
  - Updates helper startup and service wiring for menu bar support.
- `boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift`
  - Mirrors the new menu bar XPC models and protocol in the app target.
- `boringNotch/XPCHelperClient/XPCHelperClient.swift`
  - Adds asynchronous menu bar requests and Accessibility authorization monitoring.

### Notch Navigation and Presentation

- `boringNotch/BoringViewCoordinator.swift`
  - Adds menu bar and timer destinations and centralizes animated page selection.
- `boringNotch/ContentView.swift`
  - Hosts the menu bar and timer pages in the shared notch content container and coordinates their transitions and interactions.
- `boringNotch/components/Notch/BoringHeader.swift`
  - Adds header controls for the menu bar page and related navigation behavior.
- `boringNotch/components/Tabs/TabSelectionView.swift`
  - Adds the optional timer tab and stable tab identities.
- `boringNotch/enums/generic.swift`
  - Adds `activities` and `menuBar` notch destinations.
- `boringNotch/models/BoringViewModel.swift`
  - Adjusts close and reopen behavior so page transitions finish before the selected view resets.
- `boringNotch/sizing/matters.swift`
  - Adds timer and Bluetooth closed-notch activity sizes.

### Settings, Permissions, and Persistence

- `boringNotch/components/Settings/SettingsView.swift`
  - Adds Menu Bar and Timer settings, permission state controls, ordering controls, and feature toggles.
- `boringNotch/components/Settings/SettingsWindowController.swift`
  - Adds direct navigation to a requested settings tab.
- `boringNotch/components/Onboarding/OnboardingView.swift`
  - Adds first-run Accessibility and optional Screen Recording permission steps.
- `boringNotch/components/Onboarding/PermissionsRequestView.swift`
  - Changes permission copy inputs to localized string keys.
- `boringNotch/models/Constants.swift`
  - Adds persisted settings for menu bar access, previews, item order, hidden-section state, timer behavior, and Bluetooth activity.
- `boringNotch/Localizable.xcstrings`
  - Adds localized strings for menu bar access, permissions, timer and stopwatch controls, and related settings.
- `boringNotch/Info.plist`
  - Adds the Bluetooth usage description.
- `boringNotch/boringNotch.entitlements`
  - Adds the Bluetooth device entitlement.

### Application Lifecycle and Performance

- `boringNotch/boringNotchApp.swift`
  - Starts and stops the new activity services with the application lifecycle.
- `boringNotch/helpers/AppIcons.swift`
  - Adds asynchronous application icon loading and process-lifetime caching.

### Project and Documentation

- `boringNotch.xcodeproj/project.pbxproj`
  - Registers the new source files and updates project build configuration.
- `README.md`
  - Documents the added menu bar, timer, stopwatch, and Bluetooth headphone features and their references.
- `THIRD_PARTY_LICENSES`
  - Adds third-party attribution entries required by the referenced implementations.
