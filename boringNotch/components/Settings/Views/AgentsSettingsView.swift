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
    @Default(.agentsCompletionSound) private var completionSound
    @Default(.agentsCompletionSoundName) private var completionSoundName

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
                Defaults.Toggle(key: .agentsCompletionSound) {
                    Text("Play a subtle sound when an agent finishes")
                }
                .disabled(!agentsEnabled)
                Picker("Sound", selection: $completionSoundName) {
                    ForEach(AgentCompletionSound.availableSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .disabled(!agentsEnabled || !completionSound)
                .onChange(of: completionSoundName) { _, name in AgentCompletionSound.preview(name) }
            } header: {
                Text("General")
            } footer: {
                Text("While an agent is running, its status replaces the audio spectrum on the right side of the notch.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                ForEach(AgentKind.allCases, id: \.self) { agent in
                    AgentIntegrationRow(agent: agent)
                }
            } header: {
                Text("Integrations")
            } footer: {
                Text("Adds hooks to ~/.claude/settings.json and ~/.codex/hooks.json (a backup is saved first). They work in the terminal, in VS Code and in the Claude and Codex apps, and do nothing while boringCode is closed.")
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
                            Text(session.hostLabel)
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
}

private struct AgentIntegrationRow: View {
    let agent: AgentKind
    @ObservedObject private var store = AgentSessionStore.shared

    private var state: AgentHookInstaller.State { store.hookState(for: agent) }
    private var installer: AgentHookInstaller { .installer(for: agent) }
    private var title: String { agent == .claude ? "Claude Code" : "Codex" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                badge
            }
            HStack {
                Button(state == .installed ? "Reinstall hooks" : "Install hooks") {
                    store.reinstallHooks(for: agent)
                }
                .disabled(state == .agentNotFound)
                Button("Remove hooks", role: .destructive) {
                    store.uninstallHooks(for: agent)
                }
                .disabled(state == .notInstalled || state == .agentNotFound)
                Spacer()
                Button("Show \(installer.fileName)") {
                    NSWorkspace.shared.activateFileViewerSelecting([installer.fileURL])
                }
                .buttonStyle(.link)
                .disabled(state == .agentNotFound)
            }
        }
    }

    private var description: LocalizedStringKey {
        switch state {
        case .installed: "Connected — sessions will show up in the notch."
        case .notInstalled: "Not connected."
        case .outdated: "Hooks are incomplete — reinstall to fix."
        case .agentNotFound: "Not found on this Mac."
        case .error(let message): "Error: \(message)"
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch state {
        case .installed:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .outdated, .error:
            Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        case .notInstalled, .agentNotFound:
            Label("Off", systemImage: "circle")
                .foregroundStyle(.secondary)
        }
    }
}
