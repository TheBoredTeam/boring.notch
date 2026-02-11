//
//  AppearanceSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AVFoundation
import Defaults
import SwiftUI

struct Appearance: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.showMirror) var showMirror
    @Default(.mirrorShape) var mirrorShape
    @Default(.sliderColor) var sliderColor

    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"
    var body: some View {
        Form {
            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Colored spectrogram")
                }
                Defaults
                    .Toggle("Player tinting", key: .playerColorTinting)
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.rawValue)
                    }
                }
            } header: {
                Text("Media")
            }

            Section {
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Show settings icon")
                }
                Defaults.Toggle(key: .showMicrophoneButtonInNotch) {
                    Text("Show microphone mute button")
                }
                Defaults.Toggle(key: .showMuteIndicator) {
                    Text("Show mute indicator when closed")
                }
                Defaults.Toggle(key: .showMirror) {
                    Text("Enable boring mirror")
                }
                .disabled(!checkVideoInput())
                Picker("Mirror shape", selection: $mirrorShape) {
                    Text("Circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("Square")
                        .tag(MirrorShapeEnum.rectangle)
                }
                .disabled(!checkVideoInput() || !showMirror)
            } header: {
                Text("Notch buttons")
            }

            Section {
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Show cool face animation while inactive")
                }
            } header: {
                HStack {
                    Text("Additional features")
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Appearance")
    }

    func checkVideoInput() -> Bool {
        if AVCaptureDevice.default(for: .video) != nil {
            return true
        }

        return false
    }
}
