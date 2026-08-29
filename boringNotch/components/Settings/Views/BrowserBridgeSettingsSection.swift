//
//  BrowserBridgeSettingsSection.swift
//  boringNotch
//
//  Status for the "YouTube Music (Browser)" source. Shown only while that source is
//  selected, since it is meaningless otherwise.
//
//  There is nothing to pair: the bridge authorises the extension by its WebSocket
//  Origin, so this pane only reports state and offers an escape hatch for the port.
//

import Defaults
import SwiftUI

struct BrowserBridgeSettingsSection: View {
    @Default(.browserBridgePort) private var port
    @State private var isConnected = false
    @State private var extensionIdentifier: String?
    @State private var showAdvanced = false

    private let extensionURL = URL(
        string: "https://github.com/TheBoredTeam/boring.notch/tree/dev/chrome-extension"
    )!

    var body: some View {
        Section {
            HStack(spacing: 8) {
                Circle()
                    .fill(isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isConnected ? "Browser extension connected" : "Waiting for the browser extension")
                    if isConnected, let extensionIdentifier {
                        Text(extensionIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if !isConnected {
                        Text("Install the extension, then open music.youtube.com.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Link("Get the browser extension", destination: extensionURL)

            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                LabeledContent("Port") {
                    TextField("Port", value: $port, format: .number.grouping(.never))
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: port) { _, _ in
                            // Rebuilding the controller is what rebinds the listener, and is
                            // exactly what the media-source picker already triggers.
                            NotificationCenter.default.post(name: .mediaControllerChanged, object: nil)
                        }
                }
                Text("Only change this if the default port is already in use. The extension detects the port automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Browser Extension")
        } footer: {
            Text("The bridge listens only on this Mac (127.0.0.1) and accepts connections from browser extensions only — websites are refused during the WebSocket handshake.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserBridgeConnectionChanged)) { _ in
            refresh()
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        isConnected = MusicManager.shared.isActiveControllerLive
        Task { extensionIdentifier = await MusicManager.shared.connectedBrowserExtensionIdentifier }
    }
}
