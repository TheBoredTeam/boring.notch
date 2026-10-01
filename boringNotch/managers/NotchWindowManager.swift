// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

//
//  NotchWindowManager.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Extracted from AppDelegate: all notch-window, per-screen view-model and
//  drag-detector lifecycle in one place. AppDelegate keeps app-lifecycle
//  glue (shortcuts, onboarding, termination) and forwards to this manager.
//

import Combine
import Defaults
import SwiftUI

@MainActor
final class NotchWindowManager {
    /// All per-screen state in one value — replaces the parallel
    /// windows/viewModels/dragDetectors dictionaries that previously had
    /// to be mutated in lockstep (a missed mutation leaked observers).
    struct ScreenContext {
        let viewModel: BoringViewModel
        var window: NSWindow?
        var dragDetector: DragDetector?
    }

    private(set) var contexts: [String: ScreenContext] = [:] // UUID -> ScreenContext
    private(set) var primaryWindow: NSWindow?
    let primaryViewModel: BoringViewModel
    private var primaryDragDetector: DragDetector?

    private(set) var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var previousScreens: [NSScreen]?
    private struct LockedWindowConfiguration: Equatable {
        let frame: CGRect
        let safeAreaWidth: CGFloat
        let showsEmptyShape: Bool
    }
    private struct LockedWindow {
        let window: BoringNotchSkyLightWindow
        let configuration: LockedWindowConfiguration
    }
    private var lockedWindows: [String: LockedWindow] = [:]
    private var activitySubscriptions = Set<AnyCancellable>()

    init(camera: CameraModel) {
        primaryViewModel = BoringViewModel(camera: camera)
        LiveActivityCenter.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcileLockedWindows() }
            .store(in: &activitySubscriptions)
        Defaults.publisher(.showOnLockScreen)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcileLockedWindows() }
            .store(in: &activitySubscriptions)
    }

    // MARK: - Public lookups (preserve AppDelegate's old API shape)

    var windows: [String: NSWindow] {
        contexts.compactMapValues { $0.window }
    }

    var viewModels: [String: BoringViewModel] {
        contexts.mapValues { $0.viewModel }
    }

    var window: NSWindow? { primaryWindow }

    // MARK: - Screen lock / unlock

    func screenLocked() {
        isScreenLocked = true
        LiveActivityCenter.shared.updateSession(locked: true)
        primaryViewModel.close()
        contexts.values.forEach { $0.viewModel.close() }
        cleanupDragDetectors()
        cleanupWindows()
        cleanupWindows(shouldInvert: true)
        reconcileLockedWindows()
    }

    func screenUnlocked() {
        isScreenLocked = false
        LiveActivityCenter.shared.updateSession(locked: false)
        clearLockedWindows()
        adjustWindowPosition(changeAlpha: true)
        setupDragDetectors()
    }

    private func reconcileLockedWindows() {
        let center = LiveActivityCenter.shared
        guard isScreenLocked, center.session.canPresentOnLockScreen else {
            clearLockedWindows()
            return
        }
        let selected = NSScreen.screen(withUUID: BoringViewCoordinator.shared.selectedScreenUUID) ?? NSScreen.main
        let screens = Defaults[.showOnAllDisplays] ? NSScreen.screens : [selected].compactMap { $0 }
        var desiredDisplays = Set<String>()
        for screen in screens {
            guard let displayID = screen.displayUUID else { continue }
            let context = LiveActivityContext(displayID: displayID, surface: .lockScreen)
            let showsEmptyShape = Defaults[.showOnLockScreen]
            guard showsEmptyShape || center.service.snapshot(in: context).selectedID != nil else { continue }
            desiredDisplays.insert(displayID)
            let closedSize = getClosedNotchSize(screenUUID: displayID)
            let height = max(32, max(closedSize.height, screen.safeAreaInsets.top))
            let width = min(windowSize.width, screen.frame.width)
            let frame = CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height,
                               width: width, height: height)
            let configuration = LockedWindowConfiguration(frame: frame, safeAreaWidth: closedSize.width,
                                                          showsEmptyShape: showsEmptyShape)
            if lockedWindows[displayID]?.configuration == configuration { continue }
            removeLockedWindow(on: displayID)
            let window = BoringNotchSkyLightWindow(contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            window.ignoresMouseEvents = true
            window.wantsKeyForTextInput = false
            window.contentView = NSHostingView(rootView: LockedLiveActivityView(
                center: center, displayID: displayID, safeAreaWidth: closedSize.width,
                height: height, maximumWidth: width, showsEmptyShape: showsEmptyShape
            ))
            window.setFrame(frame, display: true)
            window.enableSkyLight()
            window.orderFrontRegardless()
            lockedWindows[displayID] = LockedWindow(window: window, configuration: configuration)
        }
        for displayID in Array(lockedWindows.keys) where !desiredDisplays.contains(displayID) {
            removeLockedWindow(on: displayID)
        }
    }

    private func removeLockedWindow(on displayID: String) {
        guard let window = lockedWindows.removeValue(forKey: displayID)?.window else { return }
        window.disableSkyLight()
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    private func clearLockedWindows() {
        for displayID in Array(lockedWindows.keys) { removeLockedWindow(on: displayID) }
    }

    // MARK: - Window lifecycle

    func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]

        if shouldCleanupMulti {
            for (uuid, context) in contexts {
                context.window?.close()
                if let window = context.window {
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                }
                context.dragDetector?.stopMonitoring()
                contexts.removeValue(forKey: uuid)
            }
        } else {
            primaryDragDetector?.stopMonitoring()
            primaryDragDetector = nil
            if let window = primaryWindow {
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            primaryWindow = nil
        }

        // ensure OSD integration reflects the current window state
        BoringViewCoordinator.shared.applyOSDSources()
    }

    private func createBoringNotchWindow(for screen: NSScreen, with viewModel: BoringViewModel) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]

        let window = BoringNotchSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

        // Ordinary ContentView windows never join the secure lock-screen space.
        window.disableSkyLight()

        window.contentView = NSHostingView(
            rootView: ContentView(extensionTabInput: window.extensionTabInput)
                .environmentObject(viewModel)
        )

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        // Observe when the window's screen changes so we can update drag detectors.
        // Remove any previous observer first — recreating windows used to
        // overwrite the token and leak the earlier observer each cycle.
        if let obs = windowScreenDidChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
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

    func adjustWindowPosition(changeAlpha: Bool = false) {
        guard !isScreenLocked else { reconcileLockedWindows(); return }
        let coordinator = BoringViewCoordinator.shared
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in contexts.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = contexts[uuid]?.window {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                }
                contexts[uuid]?.dragDetector?.stopMonitoring()
                contexts.removeValue(forKey: uuid)
            }

            // Create or update windows for all screens
            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }

                if contexts[uuid] == nil {
                    contexts[uuid] = ScreenContext(
                        viewModel: BoringViewModel(screenUUID: uuid, camera: primaryViewModel.camera),
                        window: nil,
                        dragDetector: nil
                    )
                }

                if contexts[uuid]?.window == nil {
                    let viewModel = contexts[uuid]!.viewModel
                    let window = createBoringNotchWindow(for: screen, with: viewModel)
                    contexts[uuid]?.window = window
                }

                if let window = contexts[uuid]?.window {
                    let viewModel = contexts[uuid]!.viewModel
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
                if let window = primaryWindow {
                    window.alphaValue = 0
                }
                return
            }

            primaryViewModel.screenUUID = selectedScreen.displayUUID
            primaryViewModel.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)

            if primaryWindow == nil {
                primaryWindow = createBoringNotchWindow(for: selectedScreen, with: primaryViewModel)
            }

            if let window = primaryWindow {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if primaryViewModel.notchState == .closed {
                    primaryViewModel.close()
                }
            }
        }

        // windows might have been added/removed during the earlier logic –
        // update the OSD subsystems accordingly.
        coordinator.applyOSDSources()
    }

    func screenConfigurationDidChange() {
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

    func noteInitialScreens() {
        previousScreens = NSScreen.screens
    }

    // MARK: - Drag detection

    func cleanupDragDetectors() {
        primaryDragDetector?.stopMonitoring()
        primaryDragDetector = nil
        for uuid in contexts.keys {
            contexts[uuid]?.dragDetector?.stopMonitoring()
            contexts[uuid]?.dragDetector = nil
        }
    }

    func setupDragDetectors() {
        cleanupDragDetectors()

        guard !isScreenLocked, Defaults[.expandedDragDetection] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = primaryWindow?.screen
                ?? NSScreen.screen(withUUID: BoringViewCoordinator.shared.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        // Per-display detectors belong to windows created by adjustWindowPosition.
        guard !Defaults[.showOnAllDisplays] || contexts[uuid]?.window != nil else { return }

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

        if Defaults[.showOnAllDisplays] {
            contexts[uuid]?.dragDetector = detector
        } else {
            primaryDragDetector = detector
        }
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard !isScreenLocked, Defaults[.boringShelf] else { return }
        guard let uuid = screen.displayUUID else { return }

        let coordinator = BoringViewCoordinator.shared
        if Defaults[.showOnAllDisplays], let viewModel = contexts[uuid]?.viewModel {
            if viewModel.open() {
                coordinator.currentView = .shelf
            }
        } else if !Defaults[.showOnAllDisplays], let windowScreen = primaryWindow?.screen, screen == windowScreen {
            if primaryViewModel.open() {
                coordinator.currentView = .shelf
            }
        }
    }

    // MARK: - Initial setup

    /// Creates the windows for the current configuration (previously inlined
    /// in applicationDidFinishLaunching).
    func prepareInitialWindows() {
        guard !isScreenLocked else { reconcileLockedWindows(); return }
        if !Defaults[.showOnAllDisplays] {
            let viewModel = primaryViewModel
            if let screen = NSScreen.main ?? NSScreen.screens.first {
                primaryWindow = createBoringNotchWindow(for: screen, with: viewModel)
            }
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        setupDragDetectors()
        noteInitialScreens()
    }

    func togglePopover(_ sender: Any?) {
        guard !isScreenLocked else { return }
        if primaryWindow?.isVisible == true {
            primaryWindow?.orderOut(nil)
        } else {
            primaryWindow?.orderFrontRegardless()
        }
    }

    func cleanup() {
        activitySubscriptions.removeAll()
        clearLockedWindows()
        cleanupDragDetectors()
        cleanupWindows()
    }
}
