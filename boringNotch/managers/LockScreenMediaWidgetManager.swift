//
//  LockScreenMediaWidgetManager.swift
//  boringNotch
//
//  A small, independent SkyLight panel for the macOS lock screen.
//

import AppKit
import Combine
import CoreGraphics
import Defaults
import SkyLightWindow
import SwiftUI

@MainActor
final class LockScreenMediaWidgetManager {
    static let shared = LockScreenMediaWidgetManager()

    private let musicManager = MusicManager.shared
    private var panelWindow: NSPanel?
    private var isSkyLightEnabled = false
    private var isLocked = false
    private var cancellables = Set<AnyCancellable>()

    private let panelSize = CGSize(width: 360, height: 108)
    private let panelCornerRadius: CGFloat = 26

    private init() {
        observeChanges()
    }

    func screenDidLock() {
        isLocked = true
        refresh()
    }

    func screenDidUnlock() {
        isLocked = false
        dismiss()
    }

    private func observeChanges() {
        musicManager.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.showOnLockScreen)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableLockScreenMediaWidget)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateSharingType()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.reposition()
            }
        }
        .store(in: &cancellables)
    }

    private var shouldDisplay: Bool {
        guard isLocked,
              Defaults[.showOnLockScreen],
              Defaults[.enableLockScreenMediaWidget]
        else { return false }

        // Do not show placeholder metadata before a media controller has supplied
        // a real track. Paused tracks with real metadata remain available.
        if musicManager.isPlaying {
            return true
        }

        let title = musicManager.songTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let artist = musicManager.artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let placeholderTitles = ["i'm handsome", "unknown", "not playing"]
        let placeholderArtists = ["me", "unknown"]
        return (!title.isEmpty && !placeholderTitles.contains(title))
            || (!artist.isEmpty && !placeholderArtists.contains(artist))
    }

    private func refresh() {
        guard shouldDisplay else {
            dismiss()
            return
        }
        present()
    }

    private func present() {
        guard let screen = targetScreen() else { return }

        let frame = LockScreenWidgetLayout.media(in: screen.frame, size: panelSize)
        let window: NSPanel

        if let existingWindow = panelWindow {
            window = existingWindow
        } else {
            let newWindow = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            newWindow.collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .fullScreenAuxiliary,
                .ignoresCycle,
            ]
            newWindow.isMovable = false
            newWindow.hasShadow = false
            newWindow.hidesOnDeactivate = false
            newWindow.acceptsMouseMovedEvents = true
            let hostingView = NSHostingView(rootView: LockScreenMediaWidgetView())
            hostingView.frame = NSRect(origin: .zero, size: panelSize)
            hostingView.autoresizingMask = [.width, .height]
            newWindow.contentView = hostingView

            if let content = newWindow.contentView {
                content.wantsLayer = true
                content.layer?.masksToBounds = true
                content.layer?.cornerRadius = panelCornerRadius
            }

            panelWindow = newWindow
            window = newWindow
        }

        window.setFrame(frame, display: true)
        updateSharingType()

        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(window)
            isSkyLightEnabled = true
        }

        window.orderFrontRegardless()
    }

    private func dismiss() {
        panelWindow?.orderOut(nil)
    }

    private func updateSharingType() {
        panelWindow?.sharingType = Defaults[.hideFromScreenRecording] ? .none : .readWrite
    }

    private func reposition() {
        guard shouldDisplay, let window = panelWindow, let screen = targetScreen() else { return }
        window.setFrame(LockScreenWidgetLayout.media(in: screen.frame, size: panelSize), display: true)
    }

    private func targetScreen() -> NSScreen? {
        // The lock screen is normally hosted by the built-in display. Falling
        // back keeps this usable on desktops and Macs without a built-in panel.
        if let builtIn = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }) {
            return builtIn
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

}
