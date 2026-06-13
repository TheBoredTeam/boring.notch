## 1. UI & First-Launch Fixes
- ContentView (boringNotch/ContentView.swift)
  * Added `.ignoresSafeArea()` to the outermost ZStack to prevent NSHostingView from being pushed down by the macOS menu bar safe area, correctly pinning the notch to the top edge.
  * Removed the `if coordinator.firstLaunch { return }` early exit inside `handleHover(_:)` to allow the notch to close on hover out even during the first launch.
- NotchHomeView (boringNotch/components/Notch/NotchHomeView.swift)
  * Removed the `if !coordinator.firstLaunch` wrapper gating `mainContent` rendering so the home view displays immediately instead of remaining blank until onboarding completes.

### 2. Leaks & Lifecycle Hardening
- VolumeManager (boringNotch/managers/VolumeManager.swift)
  * Solved CoreAudio `AudioObjectAddPropertyListenerBlock` registration memory leaks by tracking listener blocks inside a new `AudioListenerRegistration` array and removing them properly on `deinit` / via `removeAudioListeners()`. Added `[weak self]` capture checks.
- AnimatedFace (boringNotch/components/AnimatedFace.swift)
  * Fixed a lingering blink Timer leak by storing the timer instance and invalidating it on view disappearance (`.onDisappear`).
- MusicVisualizer (boringNotch/components/Music/MusicVisualizer.swift)
  * Added `dismantleNSView` handling in `AudioSpectrumView` to stop spectrum animation and invalidate the repeating timer when the view is removed.

### 3. @Observable Migration & Rendering Efficiency
- MusicManager (boringNotch/managers/MusicManager.swift)
  * Migrated `MusicManager` from legacy `ObservableObject` to the modern Swift `@Observable` macro to enable fine-grained, property-level SwiftUI updates (especially for fast-changing fields like playback position and volume).
  * Removed `@Published` attributes and replaced `@ObservedObject` references with standard properties. Marked non-UI/internal variables as `@ObservationIgnored`.
- Consumers (ContentView.swift, NotchHomeView.swift, MusicSlotConfigurationView.swift)
  * Updated declarations to use `@State` or plain properties instead of `@ObservedObject`.
  * Preserved initial publisher behaviors by migrating Combine `.onReceive` patterns to Swift's `.onChange(of:initial:true)`.

### 4. Crash Safety & Render Cleanups
- BatteryActivityManager (boringNotch/managers/BatteryActivityManager.swift)
  * Replaced an unsafe forced unwrap (`sources.first!`) with a safe `guard let` unwrapping.
- WebcamManager (boringNotch/managers/WebcamManager.swift)
  * Removed redundant manual `objectWillChange.send()` triggers on property mutations, letting the standard property tracking mechanisms handle UI refresh.
