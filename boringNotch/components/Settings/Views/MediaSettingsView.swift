//
//  MediaSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import SwiftUI

struct MediaSettingsView: View {
    @Default(.waitInterval) var waitInterval
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles
    @Default(.sliderColor) var sliderColor

    @Default(.enableLyrics) var enableLyrics
    @ObservedObject private var musicManager = MusicManager.shared

    private var realtimeAudioWaveformSupported: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }

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
                .settingsSearchAnchor(SearchKey.musicSource)
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
                .settingsSearchAnchor(SearchKey.musicLiveActivity)
                Toggle("Show sneak peek on playback changes", isOn: $enableSneakPeek)
                    .settingsSearchAnchor(SearchKey.sneakPeek)
                Picker("Sneak Peek Style", selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.localizedString).tag(style)
                    }
                }
                .settingsSearchAnchor(SearchKey.sneakPeekStyle)
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
                .settingsSearchAnchor(SearchKey.inactivityTimeout)
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
                .settingsSearchAnchor(SearchKey.fullScreenBehavior)
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
                .settingsSearchAnchor(SearchKey.lyrics)
                Defaults.Toggle(key: .showRemainingTime) {
                    Text("Show remaining time instead of duration")
                }
                .settingsSearchAnchor(SearchKey.remainingTime)
            } header: {
                Text("Media controls")
            }  footer: {
                Text("Customize which controls appear in the music player. Volume expands when active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Colored spectrogram")
                }
                .settingsSearchAnchor(SearchKey.coloredSpectrogram)
                Defaults.Toggle(key: .realtimeAudioWaveform) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Real-time audio waveform")
                        Group {
                            if realtimeAudioWaveformSupported {
                                Text("Uses Accelerate FFT on the playing app's audio. Requires audio capture permission and uses slightly more CPU.")
                            } else {
                                Text("Requires macOS 14.2 or later. Update macOS to enable real-time audio waveform.")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .disabled(!realtimeAudioWaveformSupported)
                .settingsSearchAnchor(SearchKey.realtimeWaveform)
                Defaults.Toggle(key: .playerColorTinting) {
                    Text("Player tinting")
                }
                .settingsSearchAnchor(SearchKey.playerTinting)
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                .settingsSearchAnchor(SearchKey.albumArtBlur)
                Defaults.Toggle(key: .showMediaSourceAppIcon) {
                    Text("Show source app icon on album art")
                }
                .settingsSearchAnchor(SearchKey.sourceAppIcon)
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.localizedString)
                    }
                }
                .settingsSearchAnchor(SearchKey.sliderColor)
            } header: {
                Text("Player appearance")
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

extension MediaSettingsView {
    enum SearchKey: String, SettingsSearchKey {
        case musicSource
        case musicLiveActivity
        case sneakPeek
        case sneakPeekStyle
        case inactivityTimeout
        case fullScreenBehavior
        case lyrics
        case remainingTime
        case coloredSpectrogram
        case realtimeWaveform
        case playerTinting
        case albumArtBlur
        case sourceAppIcon
        case sliderColor

        static let tab = SettingsTab.media

        var definition: SettingsSearchDefinition<Self> {
            switch self {
            case .musicSource: .init("Music Source", section: "Media Source")
            case .musicLiveActivity:
                .init("Show music live activity", section: "Media playback live activity")
            case .sneakPeek:
                .init("Show sneak peek on playback changes", section: "Media playback live activity")
            case .sneakPeekStyle: .init("Sneak Peek Style", section: "Media playback live activity")
            case .inactivityTimeout:
                .init("Media inactivity timeout", section: "Media playback live activity")
            case .fullScreenBehavior: .init("Full screen behavior", section: "Media playback live activity")
            case .lyrics: .init("Show lyrics below artist name", section: "Media controls")
            case .remainingTime: .init("Show remaining time instead of duration", section: "Media controls")
            case .coloredSpectrogram: .init("Colored spectrogram", section: "Player appearance")
            case .realtimeWaveform: .init("Real-time audio waveform", section: "Player appearance")
            case .playerTinting: .init("Player tinting", section: "Player appearance")
            case .albumArtBlur: .init("Enable blur effect behind album art", section: "Player appearance")
            case .sourceAppIcon: .init("Show source app icon on album art", section: "Player appearance")
            case .sliderColor: .init("Slider color", section: "Player appearance")
            }
        }
    }
}
