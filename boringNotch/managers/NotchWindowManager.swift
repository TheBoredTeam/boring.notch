// SPDX-License-Identifier: GPL-3.0-only

import Combine
import Defaults
import SwiftUI

@MainActor
final class NotchWindowManager {
    static let shared = NotchWindowManager()

    /// One owner per display in both single- and all-display modes.
    @MainActor
    final class ScreenContext {
        let viewModel: BoringViewModel
        let window: NSWindow
        var dragDetector: DragDetector?
        var dragGeneration = UUID()
        var screenObserver: NSObjectProtocol?

        init(viewModel: BoringViewModel, window: NSWindow) {
            self.viewModel = viewModel
            self.window = window
        }
    }

    private let store = ScreenContextStore<ScreenContext>()
    var contexts: [String: ScreenContext] { store.contexts }
    private var primaryScreenUUID: String?
    var primaryWindow: NSWindow? { primaryScreenUUID.flatMap { contexts[$0]?.window } }
    var primaryViewModel: BoringViewModel? { primaryScreenUUID.flatMap { contexts[$0]?.viewModel } }
    private(set) var isScreenLocked = false
    private var unlockTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var shelfPreferenceObserver: AnyCancellable?

    private init() {
        shelfPreferenceObserver = Defaults.publisher(.boringShelf)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setupDragDetectors() }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.screenConfigurationDidChange() }
            })
        }
    }

    var windows: [String: NSWindow] { contexts.mapValues(\.window) }
    var viewModels: [String: BoringViewModel] { contexts.mapValues(\.viewModel) }
    var window: NSWindow? { primaryWindow }

    // MARK: - Screen lock / unlock

    func screenLocked() {
        unlockTask?.cancel()
        isScreenLocked = true
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            for context in contexts.values {
                (context.window as? BoringNotchSkyLightWindow)?.enableSkyLight()
            }
        }
    }

    func screenUnlocked() {
        isScreenLocked = false
        adjustWindowPosition(changeAlpha: true)
        unlockTask?.cancel()
        // Keep the existing unlock transition, but do not let a previous unlock
        // disable SkyLight after another lock or after a window was replaced.
        let windows = contexts.values.compactMap { $0.window as? BoringNotchSkyLightWindow }
        unlockTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, !isScreenLocked else { return }
            for window in windows where contexts.values.contains(where: { $0.window === window }) {
                window.disableSkyLight()
            }
        }
    }

    // MARK: - Window lifecycle

    func cleanupWindows() {
        unlockTask?.cancel()
        store.reconcile(screens: [String: NSScreen](), create: { uuid, screen in
            createContext(for: screen, uuid: uuid)
        }, remove: dispose)
        primaryScreenUUID = nil
        BoringViewCoordinator.shared.applyOSDSources()
    }

    private func dispose(_ context: ScreenContext) {
        stopDragDetector(context)
        if let observer = context.screenObserver {
            NotificationCenter.default.removeObserver(observer)
            context.screenObserver = nil
        }
        (context.window as? BoringNotchSkyLightWindow)?.disableSkyLight()
        NotchSpaceManager.shared.notchSpace.windows.remove(context.window)
        context.window.close()
        context.window.contentView = nil
        context.viewModel.destroy()
    }

    private func createContext(for screen: NSScreen, uuid: String) -> ScreenContext {
        let viewModel = BoringViewModel(screenUUID: uuid)
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        let window = BoringNotchSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        if isScreenLocked { window.enableSkyLight() }
        window.contentView = NSHostingView(rootView: ContentView().environmentObject(viewModel))
        let context = ScreenContext(viewModel: viewModel, window: window)
        context.screenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
        ) { [weak self, weak context] _ in
            Task { @MainActor in
                guard let self, let context, self.contexts[uuid] === context,
                      let screen = NSScreen.screens.first(where: { $0.displayUUID == uuid }) else { return }
                self.setupDragDetector(for: screen, context: context)
            }
        }
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        return context
    }

    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha { window.alphaValue = 0 }
        let screenFrame = screen.frame
        window.setFrameOrigin(NSPoint(
            x: screenFrame.midX - window.frame.width / 2,
            y: screenFrame.maxY - window.frame.height
        ))
        window.alphaValue = 1
    }

    func adjustWindowPosition(changeAlpha: Bool = false) {
        guard !isScreenLocked || Defaults[.showOnLockScreen] else { return }
        let coordinator = BoringViewCoordinator.shared
        // Use one current snapshot; notification ordering must not make us use
        // an old NSScreen from the UUID cache during unplug/reconnect.
        let screens = NSScreen.screens
        let selectedScreen = screens.first { screen in
            guard let uuid = screen.displayUUID else { return false }
            return uuid == coordinator.preferredScreenUUID
        }
            ?? (Defaults[.automaticallySwitchDisplay] ? NSScreen.main ?? screens.first : nil)
        let desiredScreens = Defaults[.showOnAllDisplays] ? screens : selectedScreen.map { [$0] } ?? []
        var screensByUUID: [String: NSScreen] = [:]
        for screen in desiredScreens {
            if let uuid = screen.displayUUID { screensByUUID[uuid] = screen }
        }
        primaryScreenUUID = selectedScreen?.displayUUID
        if let primaryScreenUUID { coordinator.selectedScreenUUID = primaryScreenUUID }

        store.reconcile(screens: screensByUUID, create: { uuid, screen in
            createContext(for: screen, uuid: uuid)
        }, remove: dispose)

        for (uuid, screen) in screensByUUID {
            guard let context = contexts[uuid] else { continue }
            positionWindow(context.window, on: screen, changeAlpha: changeAlpha)
            if context.viewModel.notchState == .closed { context.viewModel.close() }
            context.window.orderFrontRegardless()
            setupDragDetector(for: screen, context: context)
        }
        coordinator.applyOSDSources()
    }

    func screenConfigurationDidChange() {
        // Reconcile every established lifecycle event: screen geometry may change
        // without changing UUIDs, and NSScreen objects are not immutable snapshots.
        NSScreenUUIDCache.shared.refresh()
        syncNotchHeightIfNeeded()
        adjustWindowPosition()
    }

    // MARK: - Drag detection

    private func stopDragDetector(_ context: ScreenContext) {
        context.dragGeneration = UUID()
        context.viewModel.dropInteraction.finish()
        context.dragDetector?.onDragEntersNotchRegion = nil
        context.dragDetector?.onDragExitsNotchRegion = nil
        context.dragDetector?.onDragEnded = nil
        context.dragDetector?.stopMonitoring()
        context.dragDetector = nil
    }

    func cleanupDragDetectors() {
        contexts.values.forEach(stopDragDetector)
    }

    func setupDragDetectors() {
        for (uuid, context) in contexts {
            guard let screen = NSScreen.screens.first(where: { $0.displayUUID == uuid }) else {
                stopDragDetector(context)
                continue
            }
            setupDragDetector(for: screen, context: context)
        }
    }

    private func setupDragDetector(for screen: NSScreen, context: ScreenContext) {
        stopDragDetector(context)
        guard Defaults[.boringShelf], let uuid = screen.displayUUID else { return }
        let detector = DragDetector()
        let generation = context.dragGeneration
        // The closed activation strip and the actual expanded destination have
        // different bounds. Opening must never be triggered by the future panel.
        detector.region = { [weak context] in
            guard let context else { return .zero }
            if context.viewModel.notchState == .open,
               let panel = context.window as? BoringNotchSkyLightWindow {
                return panel.convertToScreen(panel.interactionRect)
            }
            return context.viewModel.geometry.activationRect(on: screen.frame)
        }
        let isCurrent: () -> Bool = { [weak self, weak context] in
            guard let self, let context else { return false }
            return self.contexts[uuid] === context && context.dragGeneration == generation
                && NSScreen.screens.contains(where: { $0.displayUUID == uuid })
                && Defaults[.boringShelf]
        }
        detector.onDragEntersNotchRegion = { [weak context] in
            guard isCurrent(), Defaults[.expandedDragDetection], let context else { return }
            context.viewModel.dropInteraction.detectorTargeting = true
        }
        detector.onDragExitsNotchRegion = { [weak context] in
            guard isCurrent(), let interaction = context?.viewModel.dropInteraction else { return }
            interaction.detectorTargeting = false
            // Destination exit is debounced by ContentView so moving into the
            // growing panel does not close it between two native callbacks.
        }
        detector.onDragEnded = { [weak context] in
            // Local mouse-up monitors run before the native receiver. Let a
            // successful performDrop finish first, then discard stale callbacks.
            DispatchQueue.main.async {
                guard isCurrent() else { return }
                context?.viewModel.dropInteraction.finish()
            }
        }
        context.dragDetector = detector
        detector.startMonitoring()
    }

    // MARK: - Initial setup

    func prepareInitialWindows() {
        adjustWindowPosition(changeAlpha: true)
    }

    func togglePopover(_ sender: Any?) {
        if primaryWindow?.isVisible == true { primaryWindow?.orderOut(nil) }
        else { primaryWindow?.orderFrontRegardless() }
    }

    func cleanup() {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        cleanupWindows()
    }
}
