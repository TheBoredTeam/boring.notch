//
//  SoftwareUpdater.swift
//  boringNotch
//
//  Created by Richard Kunkli on 09/08/2024.
//

import Defaults
import Sparkle
import SwiftUI

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater
    
    init(updater: SPUUpdater) {
        self.updater = updater
        
        // Create our view model for our CheckForUpdatesView
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }
    
    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

struct UpdaterSettingsView: View {
    private let updater: SPUUpdater
    
    @Default(.updateChannel) private var updateChannel
    @Default(.updateChannelUserSelected) private var updateChannelUserSelected
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool
    
    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }
    
    var body: some View {
        Section(
            header: HStack {
                Text("Software updates")
            },
            footer: Text(
                NSLocalizedString(
                    "Stable and Beta come from official releases.",
                    comment: "Software updates channel footer"
                )
            )
        ) {
            Picker(
                NSLocalizedString("Update channel", comment: "Software updates channel picker label"),
                selection: $updateChannel
            ) {
                ForEach(UpdateChannel.visibleCases) { channel in
                    Text(channel.title).tag(channel)
                }
            }
            .onChange(of: updateChannel) { _, _ in
                updateChannelUserSelected = true
                updater.resetUpdateCycle()
            }

            Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                    updater.automaticallyChecksForUpdates = newValue
                }

            Toggle("Automatically download updates", isOn: $automaticallyDownloadsUpdates)
                .disabled(!automaticallyChecksForUpdates)
                .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                    updater.automaticallyDownloadsUpdates = newValue
                }
        }
    }
}
