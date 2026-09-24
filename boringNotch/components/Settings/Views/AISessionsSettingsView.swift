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
    @Default(.enableClaudeApprovalBridge) private var approvalBridgeEnabled
    @ObservedObject private var approvalBridge = ClaudeApprovalBridge.shared

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
            Section {
                Toggle("Show Claude Code approvals and questions", isOn: $approvalBridgeEnabled)
                    .disabled(!isEnabled)
                Text("Requires the local permission and question hooks in Claude Code settings. If Boring Notch is closed or a request times out, Claude Code keeps its native prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let errorMessage = approvalBridge.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Approvals and questions")
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled && BoringViewCoordinator.shared.currentView == .aiSessions {
                BoringViewCoordinator.shared.currentView = .home
            }
            approvalBridge.updateEnabled()
        }
        .onChange(of: approvalBridgeEnabled) { _, _ in
            approvalBridge.updateEnabled()
        }
    }
}
