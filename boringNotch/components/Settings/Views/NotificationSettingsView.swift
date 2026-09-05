//
//  NotificationSettingsView.swift
//  boringNotch
//
//  Per-app controls for the notch's notification live activity: which apps
//  are mirrored, and which of those should also have their system banner
//  auto-dismissed once captured.
//

import Defaults
import SwiftUI

private struct KnownNotificationApp: Identifiable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

private let knownNotificationApps: [KnownNotificationApp] = [
    .init(bundleID: "com.apple.MobileSMS", name: "Messages"),
    .init(bundleID: "com.apple.FaceTime", name: "FaceTime"),
    .init(bundleID: "com.apple.mail", name: "Mail"),
    .init(bundleID: "com.microsoft.Outlook", name: "Outlook"),
    .init(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp"),
    .init(bundleID: "ru.keepcoder.Telegram", name: "Telegram"),
    .init(bundleID: "com.tdesktop.Telegram", name: "Telegram Desktop"),
    .init(bundleID: "com.hnc.Discord", name: "Discord"),
    .init(bundleID: "com.anthropic.claudefordesktop", name: "Claude")
]

struct NotificationSettingsView: View {
    @Default(.notificationLiveActivity) var notificationLiveActivity
    @Default(.notificationsFromAllApps) var notificationsFromAllApps
    @Default(.notificationAllowedApps) var allowedApps

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .notificationLiveActivity) {
                    Text("Show notifications in the notch")
                }
            } footer: {
                Text("Requires Accessibility access. Only banners are mirrored — notifications delivered silently to Notification Center aren't visible to the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .notificationsFromAllApps) {
                    Text("From all apps")
                }
                .disabled(!notificationLiveActivity)

                if !notificationsFromAllApps {
                    ForEach(knownNotificationApps) { app in
                        appRow(app)
                    }
                }
            } header: {
                Text("Apps")
            } footer: {
                if !notificationsFromAllApps {
                    Text("Only these apps show a live activity in the notch. Turn on \"From all apps\" to mirror everything instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!notificationLiveActivity)

            Section {
                Defaults.Toggle(key: .smartRepliesEnabled) {
                    Text("Suggest replies with Apple Intelligence")
                }
                .disabled(!notificationLiveActivity || !smartRepliesAvailable)
            } footer: {
                Text(smartReplyFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
    }

    private var smartRepliesAvailable: Bool {
        if case .available = SmartReplyManager.availability { return true }
        return false
    }

    private var smartReplyFooter: String {
        // Drafts run entirely on-device via Apple's on-device model — no
        // network calls, nothing leaves the Mac.
        switch SmartReplyManager.availability {
        case .available:
            return "Drafts a few short reply options for messages, entirely on-device. Nothing is sent over the network."
        case .unavailable(let reason):
            return reason
        }
    }

    @ViewBuilder
    private func appRow(_ app: KnownNotificationApp) -> some View {
        HStack {
            appIcon(for: app.bundleID)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Toggle(app.name, isOn: Binding(
                get: { allowedApps.contains(app.bundleID) },
                set: { on in
                    if on { allowedApps.insert(app.bundleID) } else { allowedApps.remove(app.bundleID) }
                }
            ))
        }
        .disabled(!notificationLiveActivity)
    }
}
