//
//  AIAgentSettingsView.swift
//  boringNotch
//
//  Settings pane for the Claude Code integration. Matches boring.notch's
//  SettingsView style with grouped sections and clean visual hierarchy.
//

import SwiftUI
import Defaults

struct AIAgentSettingsView: View {
    @Default(.aiAgentEnabled) var enabled
    @Default(.aiAgentAutoOpen) var autoOpen
    @Default(.aiAgentNotifyOnDone) var notifyOnDone
    @Default(.aiAgentModel) var defaultModel
    @Default(.aiAgentWorkspace) var workspace
    @Default(.aiAgentClaudeBinary) var claudeBinaryOverride
    @Default(.aiAgentHoldExternalTools) var holdExternalTools
    @Default(.aiAgentArrivalSound) var arrivalSound
    @Default(.aiAgentDoneSound) var doneSound
    @ObservedObject private var vm = AIAgentViewModel.shared
    @State private var hooksInstalled = AgentHookInstaller.isInstalled()
    @State private var killSwitch = AgentHookInstaller.killSwitchEnabled

    var body: some View {
        Form {
            // Enable section
            Section {
                Toggle("Enable Agent tab", isOn: $enabled)
                    .tint(.effectiveAccent)
                    .onChange(of: enabled) { _, newValue in
                        if newValue {
                            AIAgentViewModel.shared.activate()
                        } else {
                            AIAgentViewModel.shared.deactivate()
                        }
                    }
                Text("Adds an Agent tab to the notch with your Claude Code sessions, and lets you approve edits and answer questions straight from the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Claude Code environment
            Section("Claude Code") {
                environmentRow(
                    label: "CLI",
                    ok: !vm.claudeMissing,
                    okText: "Found at \(vm.claudeBinary)",
                    failText: "Not found — install with: npm install -g @anthropic-ai/claude-code")

                environmentRow(
                    label: "Authentication",
                    ok: !vm.needsAuth,
                    okText: "Signed in",
                    failText: "Not signed in")

                if vm.needsAuth, !vm.claudeMissing {
                    Button("Authenticate in Terminal…") {
                        ClaudeCodeAuthOpener.openTerminalLogin()
                    }
                    .controlSize(.small)
                }

                HStack {
                    Circle()
                        .fill(vm.connected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(vm.connected
                         ? "Bridge connected — \(vm.instances.count) live session\(vm.instances.count == 1 ? "" : "s")"
                         : "Bridge idle — no live Claude Code sessions")
                        .font(.callout)
                        .foregroundStyle(vm.connected ? .primary : .secondary)
                    Spacer()
                    Button("Restart Bridge") { AIAgentViewModel.shared.restart() }
                        .controlSize(.small)
                }
                .padding(.vertical, 2)
            }

            // Hook integration
            Section("Terminal Integration") {
                HStack {
                    Image(systemName: hooksInstalled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(hooksInstalled ? Color.green : .orange)
                    Text(hooksInstalled
                         ? "Hooks installed in ~/.claude — the notch sees every session"
                         : "Hooks not installed")
                        .font(.callout)
                    Spacer()
                    Button("Reinstall") {
                        AgentHookInstaller.install()
                        hooksInstalled = AgentHookInstaller.isInstalled()
                    }
                    .controlSize(.small)
                }

                Toggle("Pause notch hooks (kill switch)", isOn: $killSwitch)
                    .tint(.effectiveAccent)
                    .onChange(of: killSwitch) { _, newValue in
                        AgentHookInstaller.killSwitchEnabled = newValue
                    }
                Text("Pauses the integration without uninstalling: Claude Code behaves exactly as if the notch were gone. Approvals fall back to the normal terminal prompts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-open notch for approvals & updates", isOn: $autoOpen)
                    .tint(.effectiveAccent)
                Toggle("Notify when Claude finishes a task", isOn: $notifyOnDone)
                    .tint(.effectiveAccent)
                Toggle("Approve terminal prompts from the notch", isOn: $holdExternalTools)
                    .tint(.effectiveAccent)
                Text("Off: terminal sessions keep Claude Code's normal approval prompts, and the notch only decides for sessions it drives. On: tool calls in every session wait for your decision here (up to 30s).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Sounds
            Section("Sounds") {
                soundPickerRow(label: "Claude needs you", binding: $arrivalSound)
                soundPickerRow(label: "Task finished", binding: $doneSound)
            }

            // Default model
            Section("Default Model") {
                Picker("Model", selection: $defaultModel) {
                    Text("Claude Code default").tag("")
                    ForEach(vm.availableModels) { m in
                        Text(m.name ?? m.id).tag(m.ref)
                    }
                }
                if !defaultModel.isEmpty {
                    Text("Used for new sessions created from the notch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Workspace
            Section("Workspace") {
                TextField("Default directory for new sessions", text: $workspace)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Text("Leave empty to use your home directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Advanced
            Section("Advanced") {
                TextField("Claude binary path (auto-detected)", text: $claudeBinaryOverride)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Text("Leave empty to auto-detect. Changes apply after reopening the Agent tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Actions
            Section {
                Button("Open Agent Window") {
                    AIAgentWindowController.shared.showWindow()
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            hooksInstalled = AgentHookInstaller.isInstalled()
        }
    }

    private func soundPickerRow(label: String, binding: Binding<String>) -> some View {
        HStack {
            Picker(label, selection: binding) {
                ForEach(Self.systemSounds, id: \.self) { sound in
                    Text(sound).tag(sound)
                }
            }
            Button {
                NSSound(named: NSSound.Name(binding.wrappedValue))?.play()
            } label: {
                Image(systemName: "play.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Preview sound")
        }
    }

    static let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    @ViewBuilder
    private func environmentRow(label: String, ok: Bool, okText: String, failText: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Color.green : .orange)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.callout.weight(.medium))
                Text(ok ? okText : failText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}