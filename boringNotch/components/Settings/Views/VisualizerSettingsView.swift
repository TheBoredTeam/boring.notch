//
//  VisualizerSettingsView.swift
//  boringNotch
//
//  Settings for the spectrum visualizer that hangs below the closed notch.
//

import Defaults
import SwiftUI

struct VisualizerSettingsView: View {
    @Default(.showNotchVisualizer) private var showNotchVisualizer
    @Default(.realtimeAudioWaveform) private var realtimeAudioWaveform
    @Default(.notchVisualizerStyle) private var style
    @Default(.notchVisualizerSensitivity) private var sensitivity
    @Default(.notchVisualizerAlbumColors) private var albumColors

    private var supported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showNotchVisualizer) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show audio visualizer under the notch")
                        Text("Reacts to the music while the notch is closed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!supported)

                if !supported {
                    Text("Requires macOS 14.2 or later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if showNotchVisualizer && !realtimeAudioWaveform {
                    // The visualizer is fed by real-time capture; offer the switch right here.
                    Defaults.Toggle(key: .realtimeAudioWaveform) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Turn on real-time audio", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("The visualizer needs real-time audio capture (also in Media). Requires audio capture permission.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Group {
                Section {
                    Picker("Style", selection: $style) {
                        ForEach(NotchVisualizerStyle.allCases) { style in
                            Text(style.localizedName).tag(style)
                        }
                    }
                    Defaults.Toggle(key: .notchVisualizerMirrored) {
                        Text("Mirror (bass in the middle)")
                    }
                    Defaults.Toggle(key: .notchVisualizerPeakCaps) {
                        Text("Peak caps")
                    }
                } header: {
                    Text("Look")
                }

                Section {
                    Defaults.Toggle(key: .notchVisualizerAlbumColors) {
                        Text("Use album art colours")
                    }
                    Defaults.Toggle(key: .notchVisualizerColorMotion) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Colours move with the music")
                            Text("The hue sways with loudness and shifts on the beat.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!albumColors)
                } header: {
                    Text("Colour")
                }

                Section {
                    LabeledContent("Sensitivity") {
                        HStack {
                            Text("Calm").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $sensitivity, in: 0...1)
                            Text("Lively").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Defaults.Toggle(key: .notchVisualizerBeatPulse) {
                        Text("Pulse on the beat")
                    }
                    Defaults.Toggle(key: .notchVisualizerBreathing) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notch breathes with the beat")
                            Text("The notch swells slightly on strong beats.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Motion")
                }

                Section {
                    Defaults.Toggle(key: .notchVisualizerLyrics) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show lyrics in the visualizer")
                            Text("Synced lyrics appear between the bars. Songs without timed lyrics keep the full visualizer.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Lyrics")
                }
            }
            .disabled(!showNotchVisualizer || !supported)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Visualizer")
    }
}
