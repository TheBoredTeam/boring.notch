//  AgentsSettingsView.swift
//  IslandNotch
//
//  Purpose: Pick the active agent (whose format left-click / auto-copy uses) and
//           the clipboard payload mode for each agent.
//  Layer: View

import SwiftUI

struct AgentsSettingsView: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section("Active agent") {
                Picker("Copy for", selection: $preferences.activeAgent) {
                    ForEach(AgentTarget.allCases) { agent in
                        Text(label(for: agent)).tag(agent)
                    }
                }
                Text("Left-clicking a thumbnail (and auto-copy) formats the clipboard for this agent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Clipboard payload per agent") {
                ForEach(AgentTarget.allCases) { agent in
                    Picker(label(for: agent), selection: payloadBinding(for: agent)) {
                        ForEach(PayloadMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }
                Text(preferences.payloadMode(for: preferences.activeAgent).explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Custom agent name") {
                TextField("Name", text: $preferences.customAgentName)
            }
        }
        .formStyle(.grouped)
    }

    private func label(for agent: AgentTarget) -> String {
        agent == .custom ? preferences.customAgentName : agent.displayName
    }

    private func payloadBinding(for agent: AgentTarget) -> Binding<PayloadMode> {
        Binding(
            get: { preferences.payloadMode(for: agent) },
            set: { preferences.setPayloadMode($0, for: agent) }
        )
    }
}
