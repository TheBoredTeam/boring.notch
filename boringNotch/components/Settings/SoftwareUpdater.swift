//
//  SoftwareUpdater.swift
//  boringNotch
//
//  Created by Richard Kunkli on 09/08/2024.
//

import AppKit
import SwiftUI

struct CheckForUpdatesView: View {
    var body: some View {
        Button("Check for Updates...") {
            if let url = URL(string: "https://github.com/TheBoredTeam/boring.notch/releases") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

struct UpdaterSettingsView: View {
    var body: some View {
        Section {
            Text("Automatic updates are disabled in this local build.")
                .foregroundStyle(.secondary)
            CheckForUpdatesView()
        } header: {
            HStack {
                Text("Software updates")
            }
        }
    }
}
