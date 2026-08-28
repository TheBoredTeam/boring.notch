//
//  MediaSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import SwiftUI

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles

    @Default(.enableLyrics) var enableLyrics

    var body: some View {
        Form {
            Section {
                MediaSourcePriorityView()
            } header: {
                Text("Media Sources")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            "Enable the sources you use and reorder them to set priority — the notch shows whichever enabled source is playing, preferring the one higher in the list."
                        )
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        HStack {
                            Text("YouTube Music requires this third-party app to be installed: ")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Link(
                                "https://github.com/pear-devs/pear-desktop",
                                destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                            )
                            .font(.caption)
                            .foregroundColor(.blue)  // Ensures it's visibly a link
                        }
                    }
                } else {
                    Text(
                        "Enable the sources you use and reorder them to set priority — the notch shows whichever enabled source is playing, preferring the one higher in the list. 'Now Playing' works with all media apps and stays last."
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            
            Section {
                Toggle(
                    "Show music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle("Show sneak peek on playback changes", isOn: $enableSneakPeek)
                Picker("Sneak Peek Style", selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.localizedString).tag(style)
                    }
                }
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text(
                                Measurement(
                                    value: Defaults[.waitInterval],
                                    unit: UnitDuration.seconds
                                ),
                                format: .measurement(
                                    width: .wide,
                                    usage: .asProvided,
                                    numberFormatStyle: .number.precision(
                                        .fractionLength(0)
                                    )
                                )
                            )
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Picker(
                    selection: $hideNotchOption,
                    label:
                        HStack {
                            Text("Full screen behavior")
                            customBadge(text: "Beta")
                        }
                ) {
                    Text("Hide for all apps").tag(HideNotchOption.always)
                    Text("Hide for media app only").tag(
                        HideNotchOption.nowPlayingOnly)
                    Text("Never hide").tag(HideNotchOption.never)
                }
            } header: {
                Text("Media playback live activity")
            }
            
            Section {
                MusicSlotConfigurationView()
                Defaults.Toggle(key: .enableLyrics) {
                    HStack {
                        Text("Show lyrics below artist name")
                        customBadge(text: "Beta")
                    }
                }
            } header: {
                Text("Media controls")
            }  footer: {
                Text("Customize which controls appear in the music player. Volume expands when active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Media")
    }
}
