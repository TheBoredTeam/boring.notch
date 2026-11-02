import SwiftUI

struct AIActivitiesSettings: View {
    @ObservedObject private var manager = AIActivityManager.shared
    @State private var previewProvider: AIProvider = .claudeCode
    @State private var previewStatus: AIActivityStatus = .working
    @State private var previewAction: AIActivityAction = .editing
    @State private var previewCompanion = false

    var body: some View {
        Form {
            Section {
                Toggle("Show AI live activities", isOn: $manager.isEnabled)
                HStack(spacing: 12) {
                    AIMascotView(provider: previewProvider, status: previewStatus, action: previewAction, size: 32)
                    Spacer()
                    TrafficLightView(status: previewStatus, diameter: 10)
                }.padding(.vertical, 8)
                Text("Red: working. Yellow: needs your attention. Green: this response finished. Inactive lamps stay dim.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("AI companions") }

            Section {
                ForEach([AIProvider.claudeCode, .codex]) { provider in
                    let connection = manager.snapshot.hookConnections[provider.rawValue] ?? AIHookConnection()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.name)
                            Group {
                                switch connection.state {
                                case .connected: Text("Hooks configured — waiting for local session events")
                                case .needsReconnect: Text("Hooks run another copy of Boring Notch or are incomplete. Reconnect to use this copy.")
                                case .notConnected: Text("Connect to receive local desktop session events")
                                }
                            }
                            .font(.caption).foregroundStyle(connection.state == .needsReconnect ? .orange : .secondary)
                            if let path = connection.executablePath {
                                Text(path).font(.caption2).foregroundStyle(.tertiary)
                                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(path)
                            }
                        }
                        Spacer()
                        if connection.state == .needsReconnect {
                            Button("Reconnect") {
                                Task { await manager.configureHooks(provider, remove: false) }
                            }.disabled(manager.isConfiguring)
                        }
                        let installed = connection.state != .notConnected
                        Button(installed ? "Disconnect" : "Connect") {
                            Task { await manager.configureHooks(provider, remove: installed) }
                        }.disabled(manager.isConfiguring)
                    }
                }
                Text("Claude Code uses Claude Desktop’s local Code sessions, including GUI sessions. After connecting, start a new session. Codex hooks must also be reviewed and trusted in /hooks. Cloud and SSH sessions need their own event bridge.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Connect preserves unrelated hooks and saves a backup. Disconnect removes only Boring Notch’s entries. Moving the app or running another build shows Reconnect.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = manager.setupMessage {
                    Text(message).font(.caption).textSelection(.enabled)
                }
            } header: { Text("Desktop event connections") }

            Section {
                Toggle("Observe ChatGPT and Claude chat windows", isOn: Binding(
                    get: { manager.observesDesktop },
                    set: { enabled in
                        if enabled { Task { await manager.enableDesktopObservation() } }
                        else { manager.observesDesktop = false }
                    }))
                Text("Uses Accessibility to inspect controls in the exposed conversation. It never opens conversations or brings an app forward. Background, minimized and hidden chats may be unobservable. A response ending without a confirmed result leaves all three lamps dim.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Some ChatGPT desktop releases share Codex’s app identity. Those Work sessions use the Codex hook connection; ordinary chat observation requires an app exposing ChatGPT controls.")
                    .font(.caption).foregroundStyle(.secondary)
                if manager.observesDesktop && !manager.snapshot.accessibilityAuthorized {
                    Button("Grant Accessibility access") { Task { await manager.enableDesktopObservation() } }
                }
            } header: { Text("Chat windows · experimental") }

            Section {
                Picker("Companion", selection: $previewProvider) {
                    ForEach(AIProvider.allCases) { Text($0.name).tag($0) }
                }
                Picker("Light", selection: $previewStatus) {
                    Text("Working · red").tag(AIActivityStatus.working)
                    Text("Attention · yellow").tag(AIActivityStatus.needsAttention)
                    Text("Finished · green").tag(AIActivityStatus.completed)
                    Text("Unconfirmed · all dim").tag(AIActivityStatus.unknown)
                }
                if previewStatus == .working {
                    Picker("Action", selection: $previewAction) {
                        ForEach(AIActivityAction.allCases, id: \.self) { action in
                            Label(action.caption(nil), systemImage: action.symbol).tag(action)
                        }
                    }
                }
                Toggle("Another AI working at the same time", isOn: $previewCompanion)
                HStack {
                    Button("Preview in notch") {
                        manager.preview(provider: previewProvider, status: previewStatus, action: previewAction,
                                        withCompanion: previewCompanion)
                    }
                        .disabled(!manager.isEnabled)
                    if manager.previewSession != nil { Button("End preview") { manager.clearPreview() } }
                }
                Text("Previews are labeled and end after 20 seconds. Live green indicators stay until you return to that app; finished responses stay in the AI tab until dismissed.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Try the lights") }

            if let message = manager.connectionMessage {
                Section { Text(message).font(.caption).textSelection(.enabled) } header: { Text("Connection") }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI Activities")
        .task { manager.start(); await manager.refreshConnections() }
    }
}
