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

import Defaults
import SwiftUI

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class NotchWindowManager {
    static let shared = NotchWindowManager()

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
    let primaryViewModel = BoringViewModel()

    private(set) var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var previousScreens: [NSScreen]?

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
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    func screenUnlocked() {
        isScreenLocked = false
        if !Defaults[.showOnLockScreen] {
            adjustWindowPosition(changeAlpha: true)
        } else {
            disableSkyLightOnAllWindows()
        }
    }

    private func enableSkyLightOnAllWindows() {
        if Defaults[.showOnAllDisplays] {
            contexts.values.forEach { context in
                (context.window as? BoringNotchSkyLightWindow)?.enableSkyLight()
            }
        } else {
            (primaryWindow as? BoringNotchSkyLightWindow)?.enableSkyLight()
        }
    }

    private func disableSkyLightOnAllWindows() {
        // Delay disabling SkyLight to avoid flicker during unlock transition
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    contexts.values.forEach { context in
                        (context.window as? BoringNotchSkyLightWindow)?.disableSkyLight()
                    }
                } else {
                    (primaryWindow as? BoringNotchSkyLightWindow)?.disableSkyLight()
                }
            }
        }
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
        } else if let window = primaryWindow {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
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

        // Enable SkyLight only when screen is locked
        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        window.contentView = FirstMouseHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )

        viewModel.$notchSize
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self, weak window] size in
                guard let self, let window else { return }
                self.resizeWindow(window, to: size)
            }
            .store(in: &viewModel.cancellables)

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        resizeWindow(window, to: viewModel.notchSize)

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

    private func resizeWindow(_ window: NSWindow, to notchSize: CGSize) {
        let targetWindowSize = CGSize(
            width: max(windowSize.width, notchSize.width),
            height: max(windowSize.height, notchSize.height + shadowPadding)
        )
        guard abs(window.frame.width - targetWindowSize.width) > 0.5
            || abs(window.frame.height - targetWindowSize.height) > 0.5
        else {
            return
        }

        let screen = window.screen
            ?? NSScreen.screen(withUUID: BoringViewCoordinator.shared.selectedScreenUUID)
            ?? NSScreen.main
        guard let screen else { return }

        let frame = NSRect(
            x: screen.frame.midX - targetWindowSize.width / 2,
            y: screen.frame.maxY - targetWindowSize.height,
            width: targetWindowSize.width,
            height: targetWindowSize.height
        )
        window.setFrame(frame, display: true, animate: false)
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
                        viewModel: BoringViewModel(screenUUID: uuid),
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
        for (_, var context) in contexts {
            context.dragDetector?.stopMonitoring()
            context.dragDetector = nil
        }
    }

    func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection] else { return }

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

        // In single-screen mode there may be no context entry yet — only
        // multi-display mode registers per-screen contexts.
        if contexts[uuid] != nil {
            contexts[uuid]?.dragDetector = detector
        } else {
            contexts[uuid] = ScreenContext(viewModel: primaryViewModel, window: nil, dragDetector: detector)
        }
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard Defaults[.boringShelf] else { return }
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
        if primaryWindow?.isVisible == true {
            primaryWindow?.orderOut(nil)
        } else {
            primaryWindow?.orderFrontRegardless()
        }
    }

    func cleanup() {
        cleanupDragDetectors()
        cleanupWindows()
    }
}
