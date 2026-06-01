//  IslandNotchApp.swift
//  IslandNotch
//
//  Purpose: App entry point. A menu-bar (LSUIElement) agent app — no main
//           window. Only a Settings scene; the AppDelegate owns the status item,
//           the floating notch, and all capture wiring.
//  Layer: App

import SwiftUI

@main
struct IslandNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The only SwiftUI scene. Settings is reachable from the menu-bar menu
        // and works under LSUIElement (no Dock icon, no default window).
        Settings {
            SettingsView()
                .environment(appDelegate.preferences)
                .environment(appDelegate.permissions)
        }
    }
}
