//
//  WebcamSettings.swift
//  boringNotch
//
//  Created by Anmol Malhotra on 2026-02-24.
//

import SwiftUI
import Defaults

struct WebcamSettings: View {

    @Default(.enableFlipWebcamToggle) private var enableFlipWebcamToggle

    var body: some View {
        Form {
            Defaults.Toggle(key: .enableFlipWebcamToggle) {
                Text("Enable toggle to flip webcam")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Webcam")
    }
}
