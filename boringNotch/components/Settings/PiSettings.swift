//
//  PiSettings.swift
//  boringNotch
//
//  Settings pane for the Pi agent tab. v1 is mostly informational — auth and the
//  model are inherited from the user's `pi` / `composio` CLI config; there are no
//  in-app keys.
//

import SwiftUI

struct PiSettings: View {
    var body: some View {
        Form {
            Section("Tools") {
                LabeledContent("Provider") {
                    Text("Composio — reusing CLI login")
                        .foregroundStyle(.secondary)
                }
                Text("Pi loads the Composio × Pi extension from your `~/.pi` config. Sign in with the `composio` CLI to connect apps like Gmail and Calendar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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
    }
}
