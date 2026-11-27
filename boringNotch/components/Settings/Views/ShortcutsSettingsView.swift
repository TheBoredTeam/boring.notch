//
//  ShortcutsSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
                    .settingsSearchAnchor(SearchKey.toggleNotchOpen)
            } header: {
                Text("Notch")
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
                    .settingsSearchAnchor(SearchKey.toggleSneakPeek)
            } header: {
                Text("Media")
            } footer: {
                Text(
                    "Sneak Peek shows the media title and artist under the notch for a few seconds."
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shortcuts")
    }
}

extension ShortcutsSettingsView {
    enum SearchKey: String, SettingsSearchKey {
        case toggleNotchOpen
        case toggleSneakPeek

        static let tab = SettingsTab.shortcuts

        var definition: SettingsSearchDefinition<Self> {
            switch self {
            case .toggleNotchOpen: .init("Toggle Notch Open:", section: "Notch")
            case .toggleSneakPeek: .init("Toggle Sneak Peek:", section: "Media")
            }
        }
    }
}
