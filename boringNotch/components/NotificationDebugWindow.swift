//
//  NotificationDebugWindow.swift
//  boringNotch
//
//  Developer window for inspecting captured Notification Center banners before
//  they are wired into the notch UI.
//

import SwiftUI

struct NotificationDebugView: View {
    @StateObject private var manager = SystemNotificationManager.shared
    @State private var replyText = ""
    @State private var axDump = ""
    @State private var lastResult = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(manager.isWatching ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(manager.isWatching ? "Watching" : "Not watching")
                Spacer()
                Button("Start") { Task { await manager.start() } }
                Button("Stop") { manager.stop() }
                Button("Clear") { manager.clear() }
                Button("Dump AX tree") { Task { axDump = await manager.debugDump() } }
            }

            if !lastResult.isEmpty {
                Text(lastResult).font(.caption).foregroundStyle(.secondary)
            }

            List(manager.notifications) { notification in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let icon = notification.icon {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                        }
                        Text(notification.appName ?? "unknown app").bold()
                        Text(notification.bundleID ?? "no bundle id")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if !notification.isLive {
                            Text("expired").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Text(notification.title ?? "—")
                    if let subtitle = notification.subtitle {
                        Text(subtitle).font(.caption)
                    }
                    Text(notification.body ?? "—").font(.caption).foregroundStyle(.secondary)
                    Text("actions: \(notification.actions.joined(separator: ", "))")
                        .font(.caption2).foregroundStyle(.tertiary)

                    HStack {
                        TextField("reply…", text: $replyText)
                            .onSubmit { send(to: notification) }
                        Button("Send") { send(to: notification) }
                            .disabled(replyText.isEmpty)
                        Button("Open") {
                            Task { await manager.open(notification) }
                        }
                    }
                    .disabled(!notification.isLive)
                }
                .padding(.vertical, 4)
            }

            if !axDump.isEmpty {
                ScrollView {
                    Text(axDump).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                .frame(height: 200)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 480)
        .task { await manager.start() }
    }

    private func send(to notification: SystemNotification) {
        let text = replyText
        replyText = ""
        Task {
            let outcome = await manager.reply(to: notification, text: text)
            switch outcome {
            case .sent:
                lastResult = "replied via the live banner"
            case .handedOffToApp:
                lastResult = "banner gone — copied to clipboard and opened the app"
            case .draftedInApp:
                lastResult = "banner gone — opened the conversation with the text pre-filled"
            case .unknown:
                lastResult = "delivery unconfirmed (deadline elapsed) — draft preserved, do not retry"
            case .failed:
                lastResult = "delivery failed (blocked) — draft preserved"
            }
        }
    }
}
