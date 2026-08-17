import SwiftUI

struct CodexNotificationSettings: View {
    @State private var isInstalled = false
    @State private var isAccessibilityAuthorized = true
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
                Text("Codex and Boring Notch show the same permission request at the same time. Allow or Deny in either place; Accessibility access lets the notch choice reach Codex.")
            }

            Section {
                LabeledContent("Status") {
                    Label(
                        isAccessibilityAuthorized ? "Granted" : "Required",
                        systemImage: isAccessibilityAuthorized
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(isAccessibilityAuthorized ? .green : .orange)
                }

                if !isAccessibilityAuthorized {
                    Button("Open Accessibility Settings") {
                        XPCHelperClient.shared.openAccessibilitySettings()
                    }
                }
            } header: {
                Text("Accessibility")
            } footer: {
                Text("Required only to send Allow or Deny from Boring Notch to the matching Codex prompt.")
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
                Text("Reconnect or restart Codex, then open /hooks in Codex and trust the updated Boring Notch hooks. Keep Accessibility enabled for Boring Notch’s helper. Hover over a permission prompt to review it; moving away collapses it back into the notch without dismissing the request.")
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
            await refreshAccessibilityStatus()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)
        ) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                isAccessibilityAuthorized = granted
            }
        }
    }

    private func refreshStatus() async {
        isInstalled = await XPCHelperClient.shared.isCodexNotificationHookInstalled()
    }

    private func refreshAccessibilityStatus() async {
        isAccessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
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
