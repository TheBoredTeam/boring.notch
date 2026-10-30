//
//  MediaSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AppKit
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

    @Default(.lastFmEnabled) private var isLastFMEnabled
    @Default(.lastFmAPIKey) private var apiKey
    @Default(.lastFmAPISecret) private var apiSecret
    @Default(.lastFmUsername) private var lastFMUsername

    @State private var lastFMToken: String = ""
    @State private var lastFMAuthURL: String = ""
    @State private var lastFMAuthError: String? = nil

    private var realtimeAudioWaveformSupported: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }

    private var lastFMIsAuthenticated: Bool {
        musicManager.lastFMIsAuthenticated
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
                Defaults.Toggle(key: .showRemainingTime) {
                    Text("Show remaining time instead of duration")
                }
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
                Defaults.Toggle(key: .playerColorTinting) {
                    Text("Player tinting")
                }
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                Defaults.Toggle(key: .showMediaSourceAppIcon) {
                    Text("Show source app icon on album art")
                }
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.localizedString)
                    }
                }
            } header: {
                Text("Player appearance")
            }

            Section {
                Defaults.Toggle(key: .lastFmEnabled) {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.right")
                        Text("Scrobble to last.fm")
                    }
                }

                if isLastFMEnabled {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Step 1: Get your API credentials")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text("Register an application at last.fm to get your API key and secret:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Link(
                                "last.fm/api/account",
                                destination: URL(string: "https://www.last.fm/api/account")!
                            )
                            .font(.caption)

                            Divider()

                            HStack {
                                Text("API Key")
                                    .frame(width: 70, alignment: .leading)
                                TextField("Your API key", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack {
                                Text("API Secret")
                                    .frame(width: 70, alignment: .leading)
                                SecureField("Your API secret", text: $apiSecret)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        if !lastFMIsAuthenticated {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Step 2: Authorize this app")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                if lastFMToken.isEmpty {
                                    Text(
                                        "Click below to request an authorization token and open the last.fm authorization page in your browser."
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                    Button("Start Authorization") {
                                        Task {
                                            await startAuthorization()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(apiKey.isEmpty || apiSecret.isEmpty)
                                } else {
                                    Text("Authorization token received. Now complete the steps:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("1. Open the authorization link below in your browser:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        HStack {
                                            Text(lastFMAuthURL)
                                                .font(.caption)
                                                .foregroundStyle(.blue)
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(8)
                                                .background(Color.secondary.opacity(0.1))
                                                .cornerRadius(6)
                                            Button {
                                                if let url = URL(string: lastFMAuthURL) {
                                                    NSWorkspace.shared.open(url)
                                                }
                                            } label: {
                                                Image(systemName: "safari")
                                            }
                                            .buttonStyle(.borderless)
                                            .help("Open in browser")
                                        }

                                        Text("2. Click \"Allow\" on the last.fm page to authorize this app")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text("3. Return here and click \"Complete Sign-in\"")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Button("Complete Sign-in") {
                                            Task {
                                                await completeAuthorization()
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }

                                if let error = lastFMAuthError {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                        Text(error)
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(8)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(6)
                                }
                            }
                        }

                        if lastFMIsAuthenticated, let username = lastFMUsername {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Connected to last.fm")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)

                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Authenticated as \(username)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Sign Out") {
                                        Task {
                                            await signOutLastFM()
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.red)
                                }

                                Text(
                                    "Scrobbling is now active. Tracks will be sent to last.fm automatically when you listen to music."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Button("Test Scrobble") {
                                    Task {
                                        await testScrobble()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(12)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.top, 8)
                }
            } header: {
                Text("last.fm Scrobbling")
            } footer: {
                Text(
                    "Automatically sends information about listened tracks to last.fm. Requires API key and authorization."
                )
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

    private func startAuthorization() async {
        lastFMAuthError = nil
        do {
            let token = try await LastFMManager.shared.requestToken()
            lastFMToken = token
            if let authURL = await LastFMManager.shared.authorizationURL(for: token) {
                lastFMAuthURL = authURL.absoluteString
                NSWorkspace.shared.open(authURL)
            }
        } catch {
            lastFMAuthError = "Failed to start authorization: \(error.localizedDescription)"
        }
    }

    private func completeAuthorization() async {
        lastFMAuthError = nil
        do {
            let response = try await LastFMManager.shared.fetchSession(token: lastFMToken)
            await LastFMManager.shared.storeSession(response)
            musicManager.lastFMIsAuthenticated = true
            musicManager.lastFMUsername = response.session.name
            lastFMToken = ""
            lastFMAuthURL = ""
        } catch {
            lastFMAuthError = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    private func signOutLastFM() async {
        await LastFMManager.shared.signOut()
        musicManager.lastFMIsAuthenticated = false
        musicManager.lastFMUsername = nil
        lastFMToken = ""
        lastFMAuthURL = ""
        lastFMAuthError = nil
    }

    private func testScrobble() async {
        let timestamp = Int(Date().timeIntervalSince1970 - 300)
        await LastFMManager.shared.testScrobble(
            artist: "Test Artist",
            title: "Test Track",
            album: "Test Album",
            duration: 300,
            timestamp: timestamp
        )
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
