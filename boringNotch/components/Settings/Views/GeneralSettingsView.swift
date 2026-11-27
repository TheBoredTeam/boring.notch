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
                .settingsSearchAnchor(SearchKey.menuBarIcon)
                LaunchAtLogin.Toggle {
                    Text("Launch at login")
                }
                .settingsSearchAnchor(SearchKey.launchAtLogin)
                Picker("Language", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .onChange(of: appLanguage) {
                    appLanguage.applyAppleLanguagesOverride()
                    showLanguageRestartAlert = true
                }
                .settingsSearchAnchor(SearchKey.language)
            } header: {
                Text("App")
            }

            Section {
                Picker("Display behavior", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .settingsSearchAnchor(SearchKey.displayBehavior)

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
                .settingsSearchAnchor(SearchKey.preferredDisplay)
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

extension GeneralSettings {
    enum SearchKey: String, SettingsSearchKey {
        case menuBarIcon
        case launchAtLogin
        case language
        case displayBehavior
        case preferredDisplay

        static let tab = SettingsTab.general

        var definition: SettingsSearchDefinition<Self> {
            switch self {
            case .menuBarIcon: .init("Show menu bar icon", section: "App")
            case .launchAtLogin: .init("Launch at login", section: "App")
            case .language: .init("Language", section: "App")
            case .displayBehavior: .init("Display behavior", section: "Displays")
            case .preferredDisplay: .init("Preferred display", section: "Displays")
            }
        }
    }
}
