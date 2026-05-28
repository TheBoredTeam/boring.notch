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
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles

    @Default(.enableLyrics) var enableLyrics

    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.localizedString).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("Media Source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
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
                } else {
                    Text(
                        "'Now Playing' was the only option on previous versions and works with all media apps."
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
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
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

            SpotifyQueueSettingsSection()
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Media")
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

private struct SpotifyQueueSettingsSection: View {
    @ObservedObject private var musicManager = MusicManager.shared

    var body: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(.secondary)
            }

            if musicManager.queueSupported {
                if musicManager.queueAuthState == .authenticated {
                    Button("Disconnect Spotify Queue") {
                        musicManager.disconnectSpotifyQueue()
                    }
                } else {
                    Button("Connect Spotify Queue") {
                        musicManager.connectSpotifyQueue()
                    }
                    .disabled(musicManager.queueAuthState == .authenticating)
                }
            } else {
                Text("Set SPOTIFY_CLIENT_ID in the Xcode build settings or Info.plist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Spotify Queue")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Queue uses the Spotify Web API. Playback controls still use AppleScript.")
                Text("In the Spotify Developer Dashboard, add redirect URI: http://127.0.0.1:8765/callback.")
                Text("Works with any music source while Spotify is playing. Add the Queue control in Media controls above.")
                Text("Tap a track in the queue to play it. Reconnect Spotify if play from queue does not work (playback permission was added).")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var statusLabel: String {
        if !musicManager.queueSupported {
            return "Not configured"
        }
        switch musicManager.queueAuthState {
        case .unauthenticated:
            return "Not connected"
        case .authenticating:
            return "Connecting..."
        case .authenticated:
            return "Connected"
        case .failed(let message):
            return message
        }
    }
}
