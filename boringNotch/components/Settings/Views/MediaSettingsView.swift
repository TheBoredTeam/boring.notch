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
    @ObservedObject private var musicManager = MusicManager.shared

    @Default(.showMediaProgressBar) private var showMediaProgressBar
    @Default(.mediaProgressBarThickness) private var mediaProgressBarThickness
    @Default(.mediaProgressBarColor) private var mediaProgressBarColor
    @Default(.mediaProgressBarUpdateInterval) private var mediaProgressBarUpdateInterval

    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: mediaControllerSelection) {
                    ForEach(MediaControllerType.allCases) { controller in
                        Text(controller.localizedResource)
                            .tag(controller)
                            .disabled(
                                controller == .nowPlaying
                                    && !musicManager.nowPlayingAvailability.isSelectable
                            )
                    }
                }
            } header: {
                Text("Media Source")
            } footer: {
                mediaSourceFooter
            }
            
            Section {
                Toggle(
                    "Show music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Defaults.Toggle(key: .showMediaProgressBar) {
                    Text("Show progress bar under notch")
                }
                if showMediaProgressBar {
                    HStack {
                        Text("Progress bar thickness")
                        Spacer()
                        Text("\(mediaProgressBarThickness, specifier: "%.1f") px")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $mediaProgressBarThickness, in: 1 ... 5, step: 0.5)
                    Picker("Progress bar color", selection: $mediaProgressBarColor) {
                        ForEach(SliderColorEnum.allCases, id: \.self) { option in
                            Text(option.localizedString)
                        }
                    }
                    Picker("Progress bar smoothness", selection: $mediaProgressBarUpdateInterval) {
                        Text("Power saver").tag(0.5)
                        Text("Balanced").tag(0.2)
                        Text("Smooth").tag(0.1)
                    }
                }
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
        .task {
            musicManager.ensureNowPlayingAvailabilityChecked()
        }
    }

    private var mediaControllerSelection: Binding<MediaControllerType> {
        Binding(
            get: { musicManager.preferredMediaController },
            set: { selectedController in
                guard selectedController != musicManager.preferredMediaController else { return }
                musicManager.selectMediaController(selectedController)
            }
        )
    }

    @ViewBuilder
    private var mediaSourceFooter: some View {
        let availability = musicManager.nowPlayingAvailability

        if availability == .checking {
            footerText("Checking Now Playing availability...")
        } else if let message = availability.settingsMessage {
            VStack(alignment: .leading, spacing: 6) {
                footerText(message)

                if musicManager.preferredMediaController == .nowPlaying,
                   let effectiveController = musicManager.effectiveMediaController,
                   effectiveController != .nowPlaying {
                    if availability.usesTemporaryFallback {
                        footerText(
                            LocalizedStringResource(
                                "Using \(effectiveController.localizedString) temporarily. Your Now Playing preference is preserved.",
                                comment: "Media settings footer for a temporary Now Playing fallback. The placeholder is the active fallback source."
                            )
                        )
                    } else {
                        footerText(
                            LocalizedStringResource(
                                "Using \(effectiveController.localizedString) instead. Your Now Playing preference is preserved.",
                                comment: "Media settings footer for a non-recoverable Now Playing setup failure. The placeholder is the active fallback source."
                            )
                        )
                    }
                }

                if availability.offersManualRetry {
                    Button("Check Again") {
                        musicManager.refreshNowPlayingAvailability()
                    }
                    .font(.caption)
                }
            }
        } else {
            footerText(
                "'Now Playing' was the only option on previous versions and works with all media apps."
            )
        }
    }

    private func footerText(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .font(.caption)
    }
}
