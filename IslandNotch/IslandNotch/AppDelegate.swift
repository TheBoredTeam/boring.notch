//  AppDelegate.swift
//  IslandNotch
//
//  Purpose: Owns the app's runtime: the status-bar item + menu, the floating
//           notch controller, the two capture hotkey paths, and the shared
//           stores. Bridges Settings toggles to the live double-⌘ event tap.
//  Layer: App

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = AppPreferences()
    let permissions = PermissionsService()
    lazy var store = ScreenshotStore(preferences: preferences)

    private lazy var notchController = NotchController(store: store, preferences: preferences)
    private let constellagentPresence = ConstellagentPresenceService()
    private let hotkeyService = HotkeyService()
    private let doubleTap = DoubleCommandTapService()
    private let menu = MenuBarMenu()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        wireCaptureSources()
        wireNotchShelfActions()
        notchController.install()
        syncConstellagentPresence()
        observeConstellagentPresence()

        Task { await store.bootstrap() }

        applyDoubleCommandSetting()
        observeDoubleCommandPreference()
        ensureScreenRecordingPermission()

        Log.app.debug("IslandNotch launched")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        permissions.refresh()
        applyDoubleCommandSetting()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "camera.viewfinder",
            accessibilityDescription: "IslandNotch"
        )
        menu.onCapture = { [weak self] in self?.triggerCapture(.menu) }
        menu.onOpenSettings = { [weak self] in self?.openSettings() }
        menu.onQuit = { NSApp.terminate(nil) }
        item.menu = menu.build()
        statusItem = item
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func wireCaptureSources() {
        hotkeyService.onCapture = { [weak self] source in self?.triggerCapture(source) }
        hotkeyService.start()
        doubleTap.onCapture = { [weak self] source in self?.triggerCapture(source) }
    }

    private func wireNotchShelfActions() {
        notchController.configureShelfActions(
            NotchController.ShelfActions(
                onCapture: { [weak self] in self?.triggerCapture(.menu) },
                onCopyLatest: { [weak self] in
                    guard let entry = self?.store.entries.first else { return }
                    self?.store.copyToClipboard(entry)
                },
                onQuickLookLatest: { [weak self] in
                    guard let self, let entry = store.entries.first else { return }
                    QuickLookService.shared.preview(entry.url(in: store.folderURL))
                }
            )
        )
    }

    func triggerCapture(_ source: CaptureSource) {
        Task {
            await store.capture(source: source)
            notchController.flashNewCapture()
        }
    }

    private func ensureScreenRecordingPermission() {
        permissions.refresh()
        guard !permissions.screenRecordingGranted else { return }
        permissions.requestScreenRecording()
    }

    private func syncConstellagentPresence() {
        notchController.setConstellagentRunning(constellagentPresence.isRunning)
    }

    private func observeConstellagentPresence() {
        withObservationTracking {
            _ = constellagentPresence.isRunning
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncConstellagentPresence()
                self?.observeConstellagentPresence()
            }
        }
    }

    func applyDoubleCommandSetting() {
        if preferences.doubleCommandEnabled {
            if !permissions.accessibilityGranted {
                permissions.requestAccessibility()
            }
            if !doubleTap.isRunning {
                _ = doubleTap.start()
            }
        } else {
            doubleTap.stop()
        }
    }

    private func observeDoubleCommandPreference() {
        withObservationTracking {
            _ = preferences.doubleCommandEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyDoubleCommandSetting()
                self?.observeDoubleCommandPreference()
            }
        }
    }
}
