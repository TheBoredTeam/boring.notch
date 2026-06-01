//  MenuBarMenu.swift
//  IslandNotch
//
//  Purpose: Builds the NSMenu shown from the status-bar item. Forwards actions
//           to the AppDelegate via closures so the menu stays UI-only.
//  Layer: View

import AppKit

final class MenuBarMenu: NSObject {
    var onCapture: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    /// Builds a fresh menu. The status item retains it for the lifetime shown.
    func build() -> NSMenu {
        let menu = NSMenu()

        let capture = NSMenuItem(
            title: "Capture Screenshot",
            action: #selector(captureAction), keyEquivalent: ""
        )
        capture.target = self
        menu.addItem(capture)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(settingsAction), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit IslandNotch",
            action: #selector(quitAction), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func captureAction() { onCapture?() }
    @objc private func settingsAction() { onOpenSettings?() }
    @objc private func quitAction() { onQuit?() }
}
