//
//  BrowserBridgeSettingsSection.swift
//  boringNotch
//
//  Pairing UI for the "YouTube Music (Browser)" source. Shown only while that source
//  is selected, since it is meaningless otherwise.
//

import Defaults
import SwiftUI

struct BrowserBridgeSettingsSection: View {
    @Default(.browserBridgePort) private var port
    @State private var token: String = BrowserBridgePairing.token
    @State private var isConnected: Bool = false
    @State private var didCopy: Bool = false

    private let extensionURL = URL(
        string: "https://github.com/TheBoredTeam/boring.notch/tree/dev/chrome-extension"
    )!

    var body: some View {
        Section {
            HStack {
                Circle()
                    .fill(isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(
                    isConnected
                        ? "Browser extension connected"
                        : "Waiting for the browser extension…"
                )
                Spacer()
            }

            LabeledContent("Pairing token") {
                HStack(spacing: 8) {
                    Text(token.isEmpty ? "—" : token)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button(didCopy ? "Copied" : "Copy") {
                        copyToken()
                    }
                    .disabled(token.isEmpty)

                    Menu {
                        Button("Regenerate Token", role: .destructive) {
                            token = BrowserBridgePairing.regenerateToken()
                            didCopy = false
                            restartBridge()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            LabeledContent("Port") {
                TextField(
                    "Port",
                    value: $port,
                    format: .number.grouping(.never)
                )
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
                .onChange(of: port) { _, _ in restartBridge() }
            }

            Link("Get the browser extension", destination: extensionURL)
        } header: {
            Text("Browser Extension")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "Install the Boring Notch extension in your browser, then paste this token into its options page to pair it."
                )
                Text(
                    "The bridge only listens on this Mac (127.0.0.1) and only accepts connections that present the token above."
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .browserBridgeConnectionChanged)
        ) { _ in
            refreshConnectionState()
        }
        .onAppear {
            token = BrowserBridgePairing.token
            refreshConnectionState()
        }
    }

    private func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { didCopy = false }
    }

    private func refreshConnectionState() {
        isConnected = MusicManager.shared.isActiveControllerLive
    }

    /// Rebuilding the controller is what actually rebinds the listener, and it is exactly
    /// what the media-source picker already does.
    private func restartBridge() {
        NotificationCenter.default.post(name: .mediaControllerChanged, object: nil)
    }
}
