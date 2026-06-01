//  SettingsView.swift
//  IslandNotch
//
//  Purpose: Root of the SwiftUI Settings scene. Tabs for General, Agents,
//           Hotkey, and Permissions. Works under LSUIElement (opened from the
//           menu-bar menu).
//  Layer: View

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AgentsSettingsView()
                .tabItem { Label("Agents", systemImage: "terminal") }
            HotkeySettingsView()
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
            PermissionsSettingsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 500, height: 380)
    }
}
