//
//  ClipboardSettingsView.swift
//  boringNotch
//
//  Created on 2026-04-13.
//

import Defaults
import SwiftUI

struct ClipboardSettings: View {
    @Default(.showClipboard) var showClipboard

    var body: some View {
        Form {
            Section {
                Toggle("Enable clipboard history", isOn: $showClipboard)
            } header: {
                Text("General")
            } footer: {
                Text("Tracks the last 5 items you copied. History is cleared when the app restarts.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Clipboard")
    }
}
