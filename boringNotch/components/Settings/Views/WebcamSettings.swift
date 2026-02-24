//
//  WebcamSettings.swift
//  boringNotch
//
//  Created by Anmol Malhotra on 23/02/2026.
//

import SwiftUI
import Defaults

struct WebcamSettings: View {
    @Default(.mirrorWebcam) private var mirrorWebcam
    @Default(.enableFlipWebcamToggle) private var enableFlipWebcamToggle

    var body: some View {
        Form {
            Toggle(isOn: $mirrorWebcam) {
                Text("Mirror webcam video")
            }
            Toggle(isOn: $enableFlipWebcamToggle) {
                Text("Enable toggle to flip webcam")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Webcam")
    }
}
