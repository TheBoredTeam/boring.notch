//
//  PiSettings.swift
//  boringNotch
//
//  Settings pane for the Pi agent tab. Auth and the model are inherited from the user's
//  `pi` / `composio` CLI config. Connected accounts (and a default account per toolkit)
//  are managed here via ComposioConnectionManager — the agent uses the default account
//  automatically, and re-auth is surfaced here instead of as a mid-turn CTA.
//

import SwiftUI

struct PiSettings: View {
    @ObservedObject private var conn = ComposioConnectionManager.shared

    var body: some View {
        Form {
            connectedAccountsSection

            Section("Model") {
                LabeledContent("Model") {
                    Text("Inherit from pi config")
                        .foregroundStyle(.secondary)
                }
                Text("The model and provider come from `~/.pi/agent/settings.json`. In-app model selection is a follow-up.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Safety") {
                LabeledContent("Tool execution") {
                    Text("Auto-run")
                        .foregroundStyle(.secondary)
                }
                Text("Every tool Pi calls runs automatically. Press ⌘. while a run is streaming to abort it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Pi")
        .onAppear { conn.refresh() }
    }

    @ViewBuilder
    private var connectedAccountsSection: some View {
        Section("Connected accounts") {
            // Re-auth prompts (expired / revoked accounts) — the out-of-band replacement
            // for the old in-notch Connect CTA.
            ForEach(conn.reauthNeeded) { need in
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(need.toolkit.capitalized + (need.alias.map { " · \($0)" } ?? ""))
                        Text(need.status.capitalized + " — needs reconnecting")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reconnect") { conn.reconnect(need) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }

            if conn.toolkits.isEmpty {
                Text("No connected apps yet. Sign in with the `composio` CLI to connect apps like Gmail and Calendar; they'll appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                // A default account per toolkit — the agent uses it automatically.
                ForEach(conn.toolkits, id: \.self) { toolkit in
                    Picker(toolkit.capitalized, selection: defaultBinding(for: toolkit)) {
                        Text("Automatic").tag("")
                        ForEach(aliases(for: toolkit), id: \.self) { alias in
                            Text(alias).tag(alias)
                        }
                    }
                }
            }

            Button("Refresh") { conn.refresh() }
                .controlSize(.small)
        }
    }

    /// Selectable default-account aliases for a toolkit (accounts without an alias can't
    /// be a default, since the agent resolves the default by alias).
    private func aliases(for toolkit: String) -> [String] {
        (conn.connections[toolkit] ?? []).compactMap(\.alias).filter { !$0.isEmpty }
    }

    /// Two-way binding for a toolkit's default alias; "" means Automatic (no default).
    private func defaultBinding(for toolkit: String) -> Binding<String> {
        Binding(
            get: { conn.defaultAliases[toolkit.lowercased()] ?? "" },
            set: { conn.setDefaultAlias($0.isEmpty ? nil : $0, for: toolkit) }
        )
    }
}
