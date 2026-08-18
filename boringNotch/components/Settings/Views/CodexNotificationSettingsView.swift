import SwiftUI

struct CodexNotificationSettings: View {
    @State private var isInstalled = false
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
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

                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                }
            } header: {
                Text("Codex task notifications")
            } footer: {
                Text("In Ask for approval mode, Boring Notch shows the request first. Allow or Deny answers Codex directly; Review in Codex hands the unresolved request to Codex's native prompt. Approve for me requests do not appear in the notch.")
            }

            Section {
                Label("The task Codex is working on", systemImage: "text.alignleft")
                Label("Success or failure status", systemImage: "checkmark.circle")
                Label("Permission, decision, or manual test needed", systemImage: "hand.raised.fill")
            } header: {
                Text("What appears in the notch")
            } footer: {
                Text("Live permission requests stay until you choose Allow or Deny or the Codex request expires. Passive Codex notices finish opening, stay for 3 seconds, then play their closing animation.")
            }

            Section("After connecting or updating") {
                Text("Restart Codex, then open /hooks in Codex and trust the updated Boring Notch hooks. Hover over a permission prompt to review it; moving away collapses it without dismissing the request.")
                    .foregroundStyle(.secondary)
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
        }
    }

    private func refreshStatus() async {
        isInstalled = await XPCHelperClient.shared.isCodexNotificationHookInstalled()
    }

    private func updateInstallation(installed: Bool) {
        isUpdating = true
        errorMessage = nil
        Task {
            let result = await XPCHelperClient.shared.setCodexNotificationHookInstalled(installed)
            switch result {
            case .success:
                isInstalled = installed
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            isUpdating = false
        }
    }
}
