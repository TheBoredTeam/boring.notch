//
//  AISessionsSettingsView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Defaults
import SwiftUI
import UserNotifications

struct AISessionsSettingsView: View {
    @Default(.enableAISessionFeature) private var isEnabled
    @Default(.enableClaudeApprovalBridge) private var approvalBridgeEnabled
    @Default(.enableAISessionCompletionNotifications) private var completionNotificationsEnabled
    @Default(.enableOpenClawBridge) private var openClawBridgeEnabled
    @ObservedObject private var approvalBridge = ClaudeApprovalBridge.shared
    @State private var hookInstallResult: String?
    @State private var enableOpenClawInternalHooks = false

    var body: some View {
        Form {
            Section {
                Toggle("Show local AI sessions in the notch", isOn: $isEnabled)
                Text("Reads recent local session files from Codex, Claude Code, and OpenClaw. Session messages are shown only in the notch and are not uploaded by this feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Recent session summaries are cached locally for up to 30 minutes to restore the view after interruption.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("To return to a terminal, focus its window once, then bind it to a session in the notch. Window binding needs Accessibility permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI Sessions")
            }
            Section {
                Toggle("Notify when a session finishes", isOn: $completionNotificationsEnabled)
                    .disabled(!isEnabled)
                Text("Completion notifications are optional and never include message content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Completion reminders")
            }
            Section {
                Toggle("Show Claude Code approvals and questions", isOn: $approvalBridgeEnabled)
                    .disabled(!isEnabled)
                Text("Requires the local permission and question hooks in Claude Code settings. If Boring Notch is closed or a request times out, Claude Code keeps its native prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Install local Claude Code hooks") {
                    do {
                        let changed = try approvalBridge.installHooks()
                        hookInstallResult = changed
                            ? "Hooks installed. A backup of the previous settings was saved."
                            : "Hooks are already installed."
                    } catch {
                        hookInstallResult = error.localizedDescription
                    }
                }
                if let hookInstallResult {
                    Text(hookInstallResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = approvalBridge.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Approvals and questions")
            }
            Section {
                Toggle("Show OpenClaw live activity and approvals", isOn: $openClawBridgeEnabled)
                    .disabled(!isEnabled)
                Text("Requires an opt-in local OpenClaw hook and plugin. Existing configuration is backed up before installation. If the receiver is unavailable, OpenClaw continues with its native behavior.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("When enabled, each tool call may appear for review. Deny blocks that call; a timeout or unavailable receiver lets OpenClaw continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Enable OpenClaw internal hooks for status questions", isOn: $enableOpenClawInternalHooks)
                    .disabled(!isEnabled)
                Text("This changes OpenClaw's global internal-hook switch and may activate other installed hooks. Leave it off to use only the plugin's session and approval events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Install local OpenClaw integration") {
                    do {
                        let changed = try OpenClawHookInstaller.install(
                            enableInternalHooks: enableOpenClawInternalHooks
                        )
                        hookInstallResult = changed
                            ? "OpenClaw integration installed. Configuration was backed up if changed. Restart the OpenClaw gateway to load it."
                            : "OpenClaw integration is already installed."
                        approvalBridge.updateEnabled()
                    } catch {
                        hookInstallResult = error.localizedDescription
                    }
                }
                if openClawBridgeEnabled && OpenClawHookInstaller.configuredToken() == nil {
                    Text("Install the local integration before live events can connect.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("OpenClaw")
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled && BoringViewCoordinator.shared.currentView == .aiSessions {
                BoringViewCoordinator.shared.currentView = .home
            }
            approvalBridge.updateEnabled()
            AISessionMonitor.shared.updateEnabled()
        }
        .onChange(of: approvalBridgeEnabled) { _, _ in
            approvalBridge.updateEnabled()
        }
        .onChange(of: openClawBridgeEnabled) { _, _ in
            approvalBridge.updateEnabled()
        }
        .onChange(of: completionNotificationsEnabled) { _, enabled in
            if enabled {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, _ in
                    if !allowed {
                        Task { @MainActor in completionNotificationsEnabled = false }
                    }
                }
            }
        }
    }
}
