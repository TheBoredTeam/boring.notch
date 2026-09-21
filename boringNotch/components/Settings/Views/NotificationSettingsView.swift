//
//  NotificationSettingsView.swift
//  boringNotch
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
    @Default(.notificationLiveActivity) private var notificationLiveActivity
    @Default(.notificationsFromAllApps) private var notificationsFromAllApps
    @Default(.notificationAllowedApps) private var allowedApps

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .notificationLiveActivity) {
                    Text("Show notifications in the notch")
                }
            } footer: {
                Text("Requires \(AccessibilityPermission.displayName). Only banners are mirrored — notifications delivered silently to Notification Center aren't visible to the app.")
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

        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
        .onChange(of: allowedApps) { _, _ in
            SystemNotificationManager.shared.updateFilter()
        }
        .onChange(of: notificationsFromAllApps) { _, _ in
            SystemNotificationManager.shared.updateFilter()
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
