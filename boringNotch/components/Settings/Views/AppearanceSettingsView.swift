//
//  AppearanceSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.sliderColor) var sliderColor
    @Default(.codexAvatarStyle) private var codexAvatarStyle
    @Default(.codexActivityEnabled) private var codexActivityEnabled
    @Default(.showNotHumanFace) private var showIdleAvatar
    @ObservedObject private var codexActivity = CodexActivityManager.shared
    @State private var previewAvatar = false

    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"

    private var realtimeAudioWaveformSupported: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }

    var body: some View {
        Form {
            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Show settings icon in notch")
                }

            } header: {
                Text("General")
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
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.localizedString)
                    }
                }
            } header: {
                Text("Media")
            }
            Section {
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Show avatar when music is idle or paused")
                }
                Toggle("Follow local Codex activity", isOn: $codexActivityEnabled)
                Text("""
                    Automatically shows Smile for no tasks, Lines for 1–2, Orbit for 3, and Colorful orbit for 4 or more. \
                    More tasks make the colorful orbit spin faster.
                    """)
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Manual avatar", selection: $codexAvatarStyle) {
                    ForEach(CodexAvatarStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .disabled(!showIdleAvatar)
                Text("The manual choice is used when live activity is off or during Preview. Live activity requires the optional local bridge.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    avatarPreview.padding(6)
                        .background(.black, in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(codexActivityEnabled ? codexActivity.statusText : "Live activity is off")
                            .font(.caption)
                        if codexActivityEnabled {
                            Text("Tasks in progress: \(codexActivity.activeCount)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Preview") { previewAvatar = true }
                        .disabled(previewAvatar)
                }
                .task(id: previewAvatar) {
                    guard previewAvatar else { return }
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    previewAvatar = false
                }
            } header: {
                HStack {
                    Text("Idle avatar")
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Appearance")
    }

    private var avatarPreview: some View {
        let style = CodexAvatarStyle.selected(manual: codexAvatarStyle, level: codexActivity.level,
                                             followsActivity: codexActivityEnabled, previewing: previewAvatar)
        return Group {
            if style == .smile {
                AnimatedFace(height: 24, width: 30)
            } else {
                CodexAvatarView(style: style, isActive: previewAvatar || (codexActivityEnabled && codexActivity.isActive),
                                speedMultiplier: previewAvatar || !codexActivityEnabled ? 1 : codexActivity.level.speedMultiplier)
            }
        }
        .frame(width: 30, height: 24)
    }
}
