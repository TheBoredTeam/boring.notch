//
//  AgentsSettingsView.swift
//  boringCode
//
//  Configurações do módulo de agentes de IA.
//

import Defaults
import SwiftUI

struct AgentsSettingsView: View {
    @ObservedObject private var store = AgentSessionStore.shared
    @Default(.agentsEnabled) private var agentsEnabled

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .agentsEnabled) {
                    Text("Monitor AI agents")
                }
                Defaults.Toggle(key: .agentsShowClosedIndicator) {
                    Text("Show status indicator in the closed notch")
                }
                .disabled(!agentsEnabled)
                Defaults.Toggle(key: .agentsHoverOpensTab) {
                    Text("Hovering the indicator opens the Agents tab")
                }
                .disabled(!agentsEnabled)
                Defaults.Toggle(key: .agentsExpandOnApproval) {
                    Text("Open the notch when an agent needs approval")
                }
                .disabled(!agentsEnabled)
            } header: {
                Text("General")
            } footer: {
                Text("While an agent is running, its status replaces the audio spectrum on the right side of the notch.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Code")
                        Text(hookStateDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    hookStateBadge
                }

                HStack {
                    Button(store.hookState == .installed ? "Reinstall hooks" : "Install hooks") {
                        store.reinstallHooks()
                    }
                    .disabled(store.hookState == .claudeNotFound)
                    Button("Remove hooks", role: .destructive) {
                        store.uninstallHooks()
                    }
                    .disabled(store.hookState == .notInstalled || store.hookState == .claudeNotFound)
                    Spacer()
                    Button("Show settings.json") {
                        NSWorkspace.shared.activateFileViewerSelecting([ClaudeHookInstaller.settingsURL])
                    }
                    .buttonStyle(.link)
                }
            } header: {
                Text("Integrations")
            } footer: {
                Text("Adds hooks to ~/.claude/settings.json (a backup is saved first). They work in the terminal, in the Claude extension for VS Code and in the Claude app, and do nothing while boringCode is closed.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                if store.sessions.isEmpty {
                    Text("No sessions right now")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.sessions) { session in
                        HStack(spacing: 8) {
                            AgentStatusIndicator(status: session.status, size: 14)
                            Text(session.projectName)
                            Text(session.host.displayName)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(session.status.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Sessions")
            }
        }
        .onAppear { store.refreshHookState() }
        .navigationTitle("AI Agents")
    }

    private var hookStateDescription: LocalizedStringKey {
        switch store.hookState {
        case .installed: "Connected — sessions will show up in the notch."
        case .notInstalled: "Not connected."
        case .outdated: "Hooks are incomplete — reinstall to fix."
        case .claudeNotFound: "Claude Code not found (~/.claude is missing)."
        case .error(let message): "Error: \(message)"
        }
    }

    @ViewBuilder
    private var hookStateBadge: some View {
        switch store.hookState {
        case .installed:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .outdated, .error:
            Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        case .notInstalled, .claudeNotFound:
            Label("Off", systemImage: "circle")
                .foregroundStyle(.secondary)
        }
    }
}
