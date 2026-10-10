//
//  GeneralSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import LaunchAtLogin
import SwiftUI

struct GeneralSettings: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @State private var showLanguageRestartAlert = false
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Default(.appLanguage) var appLanguage
    @Default(.displayMode) var displayMode

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { Defaults[.menubarIcon] },
                    set: { Defaults[.menubarIcon] = $0 }
                )) {
                    Text("Show menu bar icon")
                }
                .tint(.effectiveAccent)
                LaunchAtLogin.Toggle {
                    Text("Launch at login")
                }
                Picker("Language", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .onChange(of: appLanguage) {
                    appLanguage.applyAppleLanguagesOverride()
                    showLanguageRestartAlert = true
                }
            } header: {
                Text("App")
            }

            Section {
                Picker("Display behavior", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Picker("Preferred display", selection: $coordinator.preferredScreenUUID) {
                    ForEach(screens, id: \.uuid) { screen in
                        Text(screen.name).tag(screen.uuid as String?)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens = NSScreen.screens.compactMap { screen in
                        guard let uuid = screen.displayUUID else { return nil }
                        return (uuid, screen.localizedName)
                    }
                }
                .disabled(displayMode == .activeDisplay || displayMode == .allDisplays)
            } header: {
                Text("Displays")
            }
        }
        .toolbar {
            Button("Quit app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("General")
        .alert("Restart to apply language", isPresented: $showLanguageRestartAlert) {
            Button("Later", role: .cancel) {}
            Button("Restart Now") {
                ApplicationRelauncher.restart()
            }
        } message: {
            Text("Changing the app language requires restarting Boring Notch.")
        }
    }
}
