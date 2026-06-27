//
//  boringNotchApp.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    private let sparkleUpdaterDelegate: BoringSparkleUpdaterDelegate
    let updaterController: SPUStandardUpdaterController

    init() {
        let sparkleUpdaterDelegate = BoringSparkleUpdaterDelegate()
        self.sparkleUpdaterDelegate = sparkleUpdaterDelegate
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: sparkleUpdaterDelegate, userDriverDelegate: nil)
        SoftwareUpdateStore.updater = updaterController.updater

        // Initialize the settings window controller with the updater controller
        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        MenuBarExtra("boring.notch", systemImage: "sparkle", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            CheckForUpdatesView(updater: updaterController.updater)
            Divider()
            Button("Restart Boring Notch") {
                ApplicationRelauncher.restart()
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }
}

@MainActor
enum SoftwareUpdateStore {
    static var updater: SPUUpdater?
}

@MainActor
final class BoringSparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:] // UUID -> NSWindow
    var viewModels: [String: BoringViewModel] = [:] // UUID -> BoringViewModel
    var window: NSWindow?
    let vm: BoringViewModel = .init()
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var screenWakeObserver: Any?
    private var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector
    private var observers: [Any] = []

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush debounced shelf persistence to avoid losing recent changes
        ShelfStateViewModel.shared.flushSync()

        NotificationCenter.default.removeObserver(self)
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        if let observer = screenWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            screenWakeObserver = nil
        }
        MusicManager.shared.destroy()
        cleanupDragDetectors()
        cleanupWindows()
        BetterDisplayManager.shared.stopObserving()
        LunarManager.shared.stopListening()
        LunarManager.shared.configureLunarOSD(hide: false)
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true

        let wantLockShowcase = Defaults[.enableUnlockAnimation]
            && !coordinator.firstLaunch
            && !coordinator.helloAnimationRunning

        if Defaults[.showOnLockScreen] || wantLockShowcase {
            // 1. Lock down BEFORE the notch is presented over the lock screen, so there's never
            //    a frame where a live, openable notch shows: this gates open(), renders only the
            //    lock (+ soundwave), and force-closes any open notch.
            withAnimation(.smooth(duration: 0.4)) {
                coordinator.screenLocked = true
                vm.close()
                viewModels.values.forEach { $0.close() }
            }
            // 2. Kill AppKit-level mouse routing + tear down the global drag-to-open monitors.
            setNotchWindowsIgnoreMouse(true)
            cleanupDragDetectors()
            // 3. Present the notch over the lock screen.
            enableSkyLightOnAllWindows()
        } else {
            // Feature off and not showing on the lock screen → destroy the notch (today's behavior).
            coordinator.screenLocked = false
            cleanupWindows()
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false

        // True iff onScreenLocked kept the notch window alive over the lock screen (showcase or
        // showOnLockScreen). If so we just move it back to the desktop space; otherwise it was
        // destroyed on lock and must be rebuilt. (Capture before we clear screenLocked below.)
        let windowWasKeptAlive = coordinator.screenLocked

        // 1. Re-enable interactivity FIRST so the morph runs on a live, controllable notch.
        setNotchWindowsIgnoreMouse(false)

        // 2. Clear lock state and hand off to the open morph atomically.
        let willMorph = Defaults[.enableUnlockAnimation]
            && !coordinator.firstLaunch
            && !coordinator.helloAnimationRunning
        if willMorph {
            withAnimation(.smooth(duration: 0.45)) {
                coordinator.unlockAnimationRunning = true
                coordinator.screenLocked = false
            }
        } else {
            coordinator.screenLocked = false
        }

        // 3. Window lifecycle. The kept-alive window stays on screen so the morph plays without a
        // flash; `disableSkyLight` lifts it off the SkyLight space back onto the desktop. But that
        // window is now SkyLight-tainted and swallows desktop clicks under the notch, so once the
        // morph has finished and the notch is idle, seamlessly swap it for a pristine window
        // (drawn over the old one before closing it → no flash, clicks restored).
        if windowWasKeptAlive {
            disableSkyLightOnAllWindows()
            let swapDelay: Double = willMorph ? 2.4 : 0.3
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(swapDelay))
                self.seamlesslyRebuildNotchWindows()
            }
        } else {
            // Feature off: the window was destroyed on lock — rebuild it.
            adjustWindowPosition(changeAlpha: true)
        }

        // 4. Rebuild the drag detectors torn down on lock.
        setupDragDetectors()
    }
    
    /// While locked, make the notch window(s) ignore mouse events so clicks/hover route straight
    /// to the lock screen behind — belt-and-suspenders to SwiftUI's `allowsHitTesting`.
    @MainActor
    private func setNotchWindowsIgnoreMouse(_ ignore: Bool) {
        let apply: (NSWindow) -> Void = { $0.ignoresMouseEvents = ignore }
        if Defaults[.showOnAllDisplays] {
            windows.values.forEach(apply)
        } else if let window = window {
            apply(window)
        }
    }

    @MainActor
    private func enableSkyLightOnAllWindows() {
        if Defaults[.showOnAllDisplays] {
            windows.values.forEach { window in
                if let skyWindow = window as? BoringNotchSkyLightWindow {
                    skyWindow.enableSkyLight()
                }
            }
        } else {
            if let skyWindow = window as? BoringNotchSkyLightWindow {
                skyWindow.enableSkyLight()
            }
        }
    }
    
    @MainActor
    private func disableSkyLightOnAllWindows() {
        // Delay disabling SkyLight to avoid flicker during unlock transition
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    self.windows.values.forEach { window in
                        if let skyWindow = window as? BoringNotchSkyLightWindow {
                            skyWindow.disableSkyLight()
                        }
                    }
                } else {
                    if let skyWindow = self.window as? BoringNotchSkyLightWindow {
                        skyWindow.disableSkyLight()
                    }
                }
            }
        }
    }

    /// Retire each SkyLight-tainted notch window by moving its LIVE content onto a brand-new,
    /// never-delegated window — pixel-seamlessly (no flash, no chin discontinuity).
    ///
    /// Why this exists: SkyLight delegation (`enableSkyLight` on lock) leaves persistent
    /// server-side state on the window that survives `undelegateWindow` + re-adding it to the
    /// high-level `notchSpace` (`disableSkyLight`). The symptom is that the transparent 640px
    /// margins start swallowing desktop clicks near/under the notch after an unlock. A fresh
    /// window — new `windowNumber`, never delegated to SkyLight — is the only reliable cure.
    ///
    /// Seamlessness has two independent requirements that together forced this design:
    ///   • CHIN CONTINUITY → we must REUSE the same `NSHostingView`. A *fresh* view cannot match
    ///     the old one for one frame: `AudioSpectrum` drives each bar with a `CAKeyframeAnimation`
    ///     whose `beginTime` is `CACurrentMediaTime()`-relative (MusicVisualizer.swift), so a new
    ///     instance re-phases the waveform; and the album art's `matchedGeometryEffect` namespace
    ///     is per-`ContentView`. Reusing the instance keeps both byte-identical (a fresh view gave
    ///     a 1-frame flash on the left/right chins).
    ///   • NO BLANK FRAME → reparenting that live view detaches it from the old window the instant
    ///     it is moved, while its layer's backing surface re-hosts onto the new window
    ///     ASYNCHRONOUSLY — a sub-frame gap where the notch had no drawn pixels (an earlier reparent
    ///     flashed the whole notch). We bridge that gap with a STATIC SNAPSHOT of the live view's
    ///     current pixels, placed BENEATH the live view inside the new window. Something
    ///     pixel-identical always occupies the notch during the re-host; once the live view's
    ///     surface populates it covers the snapshot, and the snapshot is removed a runloop turn
    ///     later. The reused view keeps animating throughout, so any residual delta is <1 frame.
    ///
    /// The container is a `NotchPassthroughContainerView` so transparent margins still pass desktop
    /// clicks through exactly as when the hosting view is the window's content view directly.
    /// State continuity holds because the moved view already binds the SAME view model.
    /// Call this only once the unlock morph has finished and the notch is idle.
    @MainActor
    private func seamlesslyRebuildNotchWindows() {
        /// Static bitmap of `view`'s current pixels (synchronous, in-process; unaffected by
        /// `sharingType == .none`, which only blocks out-of-process capture).
        func snapshotView(of view: NSView) -> NSImageView {
            let b = view.bounds
            let iv = NSImageView(frame: b)
            iv.imageScaling = .scaleNone
            iv.wantsLayer = true
            iv.autoresizingMask = [.width, .height]
            if b.width > 0, b.height > 0, let rep = view.bitmapImageRepForCachingDisplay(in: b) {
                view.cacheDisplay(in: b, to: rep)
                let img = NSImage(size: b.size)
                img.addRepresentation(rep)
                iv.image = img
            }
            return iv
        }

        /// Build the pristine replacement and move `oldWindow`'s live view onto it, bridged by a
        /// snapshot. `oldWindow.contentView` is read but the snapshot/live both live in the NEW
        /// window, so the notch position is never blank. Returns the new window + the snapshot to
        /// drop later. Nil if the old window has no content view.
        func bridgeReparent(from oldWindow: NSWindow, bind viewModel: BoringViewModel, on screen: NSScreen) -> (new: NSWindow, snapshot: NSImageView)? {
            guard let liveView = oldWindow.contentView else { return nil }

            let newWindow = createBoringNotchWindow(for: screen, with: viewModel, installContentView: false)
            newWindow.alphaValue = 1
            let f = screen.frame
            newWindow.setFrameOrigin(NSPoint(
                x: f.origin.x + (f.width / 2) - newWindow.frame.width / 2,
                y: f.origin.y + f.height - newWindow.frame.height
            ))

            // Container: frozen snapshot at the bottom; the live view goes above it once the window
            // is drawn. Passthrough hit-testing preserves margin click-through.
            let container = NotchPassthroughContainerView(frame: NSRect(origin: .zero, size: newWindow.frame.size))
            container.wantsLayer = true
            container.autoresizesSubviews = true
            let snapshot = snapshotView(of: liveView)   // captured while still on the old window
            snapshot.frame = container.bounds
            container.addSubview(snapshot)
            newWindow.contentView = container

            // Stack the new window above the old one and draw the frozen bitmap NOW.
            newWindow.orderFrontRegardless()
            NotchSpaceManager.shared.notchSpace.windows.insert(newWindow)
            container.layoutSubtreeIfNeeded()
            newWindow.displayIfNeeded()
            CATransaction.flush()                       // frozen bitmap is live server-side

            // Move the LIVE view above the snapshot. This detaches it from the old window (which
            // goes blank, but is behind the new window's snapshot), and re-hosts its surface onto
            // the new window — covered by the snapshot beneath until it populates.
            liveView.frame = container.bounds
            liveView.autoresizingMask = [.width, .height]
            container.addSubview(liveView, positioned: .above, relativeTo: snapshot)
            liveView.layoutSubtreeIfNeeded()
            liveView.layer?.layoutIfNeeded()
            CATransaction.flush()                       // force the live surface to populate
            return (newWindow, snapshot)
        }

        /// One runloop turn later the live view is drawn: drop the snapshot and retire the old
        /// window in one coalesced flush, revealing the live (same-phase, still-animating) view.
        func finish(old: NSWindow, snapshot: NSImageView) {
            NSDisableScreenUpdates()
            old.orderOut(nil)
            NotchSpaceManager.shared.notchSpace.windows.remove(old)
            old.close()                                 // isReleasedWhenClosed == false
            snapshot.removeFromSuperview()
            NSEnableScreenUpdates()
        }

        if Defaults[.showOnAllDisplays] {
            var pending: [(old: NSWindow, snapshot: NSImageView)] = []
            for uuid in Array(windows.keys) {
                guard let oldWindow = windows[uuid],
                      let viewModel = viewModels[uuid],
                      oldWindow.contentView != nil,
                      let screen = oldWindow.screen ?? NSScreen.screen(withUUID: uuid) else { continue }
                // createBoringNotchWindow overwrites `windowScreenDidChangeObserver` each call;
                // remove the prior token per iteration (the old multi-display path leaked them).
                let oldObserver = windowScreenDidChangeObserver
                guard let r = bridgeReparent(from: oldWindow, bind: viewModel, on: screen) else { continue }
                if let oldObserver { NotificationCenter.default.removeObserver(oldObserver) }
                windows[uuid] = r.new
                pending.append((oldWindow, r.snapshot))
            }
            DispatchQueue.main.async {
                pending.forEach { finish(old: $0.old, snapshot: $0.snapshot) }
                self.setupDragDetectors()
                self.coordinator.applyOSDSources()
            }
        } else {
            guard let oldWindow = window, oldWindow.contentView != nil,
                  let screen = oldWindow.screen
                    ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                    ?? NSScreen.main else { return }
            let oldObserver = windowScreenDidChangeObserver
            guard let r = bridgeReparent(from: oldWindow, bind: vm, on: screen) else { return }
            window = r.new
            if let oldObserver { NotificationCenter.default.removeObserver(oldObserver) }
            DispatchQueue.main.async {
                finish(old: oldWindow, snapshot: r.snapshot)
                self.setupDragDetectors()
                self.coordinator.applyOSDSources()
            }
        }
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]
        
        if shouldCleanupMulti {
            windows.values.forEach { window in
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            self.window = nil
        }

        // ensure OSD integration reflects the current window state
        coordinator.applyOSDSources()
    }

    private func cleanupDragDetectors() {
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = window?.screen
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        let screenFrame = screen.frame
        let notchHeight = openNotchSize.height
        let notchWidth = openNotchSize.width
        
        // Create notch region at the top-center of the screen where an open notch would occupy
        let notchRegion = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        
        let detector = DragDetector(notchRegion: notchRegion)
        
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }
        
        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard Defaults[.boringShelf] else { return }
        guard let uuid = screen.displayUUID else { return }
        
        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            if viewModel.open() {
                coordinator.currentView = .shelf
            }
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen, screen == windowScreen {
            if vm.open() {
                coordinator.currentView = .shelf
            }
        }
    }

    /// - Parameter installContentView: when `false`, the window is created bare — no hosting view,
    ///   not ordered front, not inserted into `notchSpace`. The caller is then responsible for
    ///   supplying a content view (e.g. by reparenting a live one) and doing the ordering/insertion,
    ///   all under its own screen-updates guard. See `seamlesslyRebuildNotchWindows`.
    private func createBoringNotchWindow(for screen: NSScreen, with viewModel: BoringViewModel, installContentView: Bool = true) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]

        let window = BoringNotchSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

        // Enable SkyLight only when screen is locked; a window born during lock must also be
        // non-interactive (no opening the notch on the lock screen).
        if isScreenLocked {
            window.enableSkyLight()
            window.ignoresMouseEvents = true
        } else {
            window.disableSkyLight()
        }

        if installContentView {
            window.contentView = NSHostingView(
                rootView: ContentView()
                    .environmentObject(viewModel)
            )

            window.orderFrontRegardless()
            NotchSpaceManager.shared.notchSpace.windows.insert(window)
        }

        // Observe when the window's screen changes so we can update drag detectors
        windowScreenDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDragDetectors()
                }
        }
        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
        window.alphaValue = 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            Task { @MainActor in
                window.alphaValue = self.coordinator.selectedScreenUUID == self.coordinator.preferredScreenUUID ? 1 : 0
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        })

        // Use closure-based observers for DistributedNotificationCenter and keep tokens for removal
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenUnlocked(notification)
                }
        }

        // Safety net: if the screen wakes without a lock-screen unlock event (e.g. sleep/wake
        // with no password required), never leave the notch window stuck delegated to the
        // SkyLight space above other apps.
        screenWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.isScreenLocked, self.coordinator.screenLocked else { return }
                    self.coordinator.screenLocked = false
                    self.setNotchWindowsIgnoreMouse(false)
                    self.disableSkyLightOnAllWindows()
                    self.setupDragDetectors()
                    // The window was SkyLight-delegated on lock; swap it for a pristine one so it
                    // stops swallowing desktop clicks under the notch (see seamlesslyRebuildNotchWindows).
                    try? await Task.sleep(for: .seconds(0.3))
                    self.seamlesslyRebuildNotchWindows()
                }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            if Defaults[.sneakPeekStyles] == .inline {
                let newStatus = !self.coordinator.expandingView.show
                self.coordinator.toggleExpandingView(status: newStatus, type: .music)
                KeyboardShortcuts.onKeyUp(for: .toggleSneakPeek) {
                    self.coordinator.toggleSneakPeek(
                        status: !self.coordinator.isAnySneakPeekShowing,
                        type: .music
                    )
                }
            } else {
                self.coordinator.toggleSneakPeek(
                    status: !self.coordinator.isAnySneakPeekShowing,
                    type: .music,
                    duration: 3.0
                )
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }

                let mouseLocation = NSEvent.mouseLocation

                var viewModel = self.vm

                if Defaults[.showOnAllDisplays] {
                    for screen in NSScreen.screens {
                        if screen.frame.contains(mouseLocation) {
                            if let uuid = screen.displayUUID, let screenViewModel = self.viewModels[uuid] {
                                viewModel = screenViewModel
                                break
                            }
                        }
                    }
                }

                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    var didOpen = false
                    await MainActor.run {
                        didOpen = viewModel.open()
                    }
                    guard didOpen else { return }

                    let task = Task { [weak viewModel] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.close()
                            }
                        } catch { }
                    }
                    self.closeNotchTask = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        // Sync notch height with real value on app launch if mode is matchRealNotchSize
        syncNotchHeightIfNeeded()
        
        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createBoringNotchWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        setupDragDetectors()

        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        } else if MusicManager.shared.isNowPlayingDeprecated
            && Defaults[.mediaController] == .nowPlaying
        {
            DispatchQueue.main.async {
                self.showOnboardingWindow(step: .musicPermission)
            }
        }

        previousScreens = NSScreen.screens

        // make sure OSD subsystems are in the right state now that initial
        // notch windows have been created/cleaned up
        coordinator.applyOSDSources()
    }

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "boring", fileExtension: "m4a")
    }

    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }

    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                // Sync notch height with real value if mode is matchRealNotchSize
                syncNotchHeightIfNeeded()
                
                self?.cleanupWindows()
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in windows.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    windows.removeValue(forKey: uuid)
                    viewModels.removeValue(forKey: uuid)
                }
            }

            // Create or update windows for all screens
            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }
                
                if windows[uuid] == nil {
                    let viewModel = BoringViewModel(screenUUID: uuid)
                    let window = createBoringNotchWindow(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)

                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screen(withUUID: coordinator.preferredScreenUUID ?? "") {
                coordinator.selectedScreenUUID = coordinator.preferredScreenUUID ?? ""
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main,
                      let mainUUID = mainScreen.displayUUID {
                coordinator.selectedScreenUUID = mainUUID
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }

            vm.screenUUID = selectedScreen.displayUUID
            vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)

            if window == nil {
                window = createBoringNotchWindow(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }

        // windows might have been added/removed during the earlier logic –
        // update the OSD subsystems accordingly.
        coordinator.applyOSDSources()
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Onboarding"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.level = .floating
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    step: step,
                    updater: SoftwareUpdateStore.updater,
                    onFinish: {
                        window.orderOut(nil)
//                        NSApp.setActivationPolicy(.accessory)
                        window.close()
                        NSApp.deactivate()
                    },
                    onOpenSettings: {
                        window.close()
                        SettingsWindowController.shared.showWindow()
                    }
                ))
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            onboardingWindowController = NSWindowController(window: window)
        }

//        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.level = .floating
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
}

/// A notch-window content view that never claims a click for itself. It only returns hits on its
/// subviews (the live notch hosting view); a point that lands on nothing but the container itself
/// returns `nil`, so the transparent margins pass desktop clicks through to the window behind —
/// exactly as when the `NSHostingView` is the window's content view directly. Used by
/// `seamlesslyRebuildNotchWindows` to wrap the reused hosting view + its bridging snapshot without
/// reintroducing the under-the-notch click-swallow bug.
final class NotchPassthroughContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}
