import SwiftUI

struct CodexNotificationSettings: View {
    @State private var isInstalled = false
    @State private var hooksAreTrusted = false
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Connection Status") {
                    Label(
                        isInstalled ? "Connected" : "Not connected",
                        systemImage: isInstalled ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(isInstalled ? .green : .secondary)
                }

                Button(isInstalled ? "Disconnect Codex" : "Connect or update Codex") {
                    updateInstallation(installed: !isInstalled)
                }
                .disabled(isUpdating)

                LabeledContent("Hook Status") {
                    CodexHookStatusLabel(
                        isInstalled: isInstalled,
                        hooksAreTrusted: hooksAreTrusted
                    )
                }

                if isInstalled && !hooksAreTrusted {
                    Button("Trust hooks in Codex", action: openCodexHooks)
                        .disabled(isUpdating)
                }

                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                }
            } header: {
                Text("Codex task notifications")
            }

            Section("Notification types") {
                CodexNotificationTypeRow(
                    title: "Success",
                    detail: "The task completed successfully.",
                    icon: .system(CodexJobStatus.succeeded.icon)
                )
                CodexNotificationTypeRow(
                    title: "Failure",
                    detail: "Codex stopped with an error.",
                    icon: .system(CodexJobStatus.failed.icon)
                )
                CodexNotificationTypeRow(
                    title: "Permission Required",
                    detail: "A Codex tool needs your Allow or Deny response.",
                    icon: .asset("codexSettingsShield")
                )
                CodexNotificationTypeRow(
                    title: "Decision Required",
                    detail: "Codex needs you to choose between options.",
                    icon: .system(CodexJobStatus.needsAction(.decision).icon)
                )
                CodexNotificationTypeRow(
                    title: "Manual review",
                    detail: "A result needs you to inspect or approve it.",
                    icon: .system(CodexJobStatus.needsAction(.manualCheck).icon)
                )
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await refreshStatus()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await refreshStatus()
            }
        }
    }

    private func refreshStatus() async {
        let installed = await XPCHelperClient.shared.isCodexNotificationHookInstalled()
        isInstalled = installed
        if installed {
            hooksAreTrusted = await XPCHelperClient.shared.areCodexNotificationHooksTrusted()
        } else {
            hooksAreTrusted = false
        }
    }

    private func updateInstallation(installed: Bool) {
        isUpdating = true
        errorMessage = nil
        Task {
            let result = await XPCHelperClient.shared.setCodexNotificationHookInstalled(installed)
            switch result {
            case .success:
                await refreshStatus()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            isUpdating = false
        }
    }

    private func openCodexHooks() {
        guard let hooksURL = URL(string: "codex://settings") else { return }
        CodexNotificationManager.shared.openCodex(at: hooksURL)
    }
}

private struct CodexHookStatusLabel: View {
    let isInstalled: Bool
    let hooksAreTrusted: Bool

    var body: some View {
        Label(statusTitle, systemImage: statusIcon)
            .foregroundStyle(statusColor)
    }

    private var statusTitle: String {
        if !isInstalled { return "Connect Codex first" }
        return hooksAreTrusted ? "Trusted" : "Needs trust"
    }

    private var statusIcon: String {
        if !isInstalled { return "circle" }
        return hooksAreTrusted
            ? "checkmark.circle.fill"
            : "xmark.circle.fill"
    }

    private var statusColor: Color {
        if !isInstalled { return .secondary }
        return hooksAreTrusted ? .green : .red
    }
}

private enum CodexNotificationTypeIcon {
    case system(String)
    case asset(String)
}

private struct CodexNotificationTypeRow: View {
    let title: String
    let detail: String
    let icon: CodexNotificationTypeIcon

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
        case .asset(let name):
            Image(name)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            iconView
                .frame(width: 18)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
