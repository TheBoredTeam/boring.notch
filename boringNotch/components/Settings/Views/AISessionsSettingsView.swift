//
//  AISessionsSettingsView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Defaults
import SwiftUI

struct AISessionsSettingsView: View {
    @Default(.enableAISessionFeature) private var isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Show local AI sessions in the notch", isOn: $isEnabled)
                Text("Reads recent Codex and Claude Code session files on this Mac. Session messages are shown only in the notch and are not uploaded by this feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI Sessions")
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled && BoringViewCoordinator.shared.currentView == .aiSessions {
                BoringViewCoordinator.shared.currentView = .home
            }
        }
    }
}
