//  HotkeySettingsView.swift
//  IslandNotch
//
//  Purpose: Configure the global capture shortcut (KeyboardShortcuts) and toggle
//           the double-⌘ gesture (which the AppDelegate applies on change).
//  Layer: View

import KeyboardShortcuts
import SwiftUI

struct HotkeySettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(PermissionsService.self) private var permissions

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section("Global shortcut") {
                KeyboardShortcuts.Recorder("Capture screenshot:", name: .captureScreenshot)
                Text("A normal keyboard chord. Works without any special permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("⌘ gesture") {
                Toggle("Capture with ⌘ gestures", isOn: $preferences.doubleCommandEnabled)
                Text("Double-tap either ⌘ key, or press the left and right ⌘ keys together. Holding other modifiers cancels the gesture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !permissions.accessibilityGranted {
                    HStack(spacing: 8) {
                        Label("Needs Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Spacer()
                        Button("Open Settings") { SystemSettingsLinks.open(SystemSettingsLinks.accessibility) }
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { permissions.refresh() }
    }
}
