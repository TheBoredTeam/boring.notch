//
//  SystemSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// Settings for the expanded-only System sections. The Developer section joins this pane
/// rather than claiming one of its own.
struct SystemSettings: View {
    @Default(.showNetworkInformation) var showNetworkInformation

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showNetworkInformation) {
                    Text("Show network information")
                }
                Defaults.Toggle(key: .showPublicIPAddress) {
                    Text("Look up public IP address")
                }
                .disabled(!showNetworkInformation)
            } header: {
                Text("Network")
            } footer: {
                HelpText("Speeds are read from the system and appear only when the notch is open — nothing is measured while it is closed, and no data is sent anywhere to determine them.\n\nLooking up the public IP address is the exception: it contacts an external service, so it is off by default. It is requested once per connection, not repeatedly.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("System")
    }
}

#Preview {
    SystemSettings()
        .frame(width: 500, height: 400)
}
