//
//  PrivacySettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct PrivacySettings: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .microphoneActivity) {
                    Text("Show microphone activity")
                }
                Defaults.Toggle(key: .cameraActivity) {
                    Text("Show camera activity")
                }
            } header: {
                Text("Privacy")
            } footer: {
                HelpText("A brief activity appears when the microphone or camera starts and stops being used. While either stays in use, open the notch to see it.")
            }

            Section {
                HelpText("Microphone use is reported by the audio system, which also names the app responsible. Helper processes are shown as the app they belong to.\n\nmacOS provides no way for an app to learn which program is using the camera, so camera activity is shown without a name. Finding that out would require private system interfaces, which this app does not use.\n\nListening that the system does on its own — Siri and dictation — is not shown, because macOS already displays its own indicator for it. Detection follows your default input device.")
            } header: {
                Text("About privacy detection")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Privacy")
    }
}

#Preview {
    PrivacySettings()
        .frame(width: 500, height: 400)
}
