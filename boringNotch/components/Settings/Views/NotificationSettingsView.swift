//
//  NotificationSettingsView.swift
//  boringNotch
//
import AppKit
import Defaults
import SwiftUI

private struct NotificationApp: Identifiable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}

struct NotificationSettingsView: View {
    @Default(.notificationLiveActivity) private var notificationLiveActivity
    @Default(.notificationsFromAllApps) private var notificationsFromAllApps
    @Default(.notificationAllowedApps) private var allowedApps
    @State private var isAccessibilityAuthorized = true

    @MainActor private var selectedApps: [NotificationApp] {
        allowedApps
            .map { NotificationApp(bundleID: $0, name: displayName(for: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .notificationLiveActivity) {
                    Text("Show notifications in the notch")
                }
            } footer: {
                Text("Requires \(AccessibilityPermission.displayName). Only visible banners are mirrored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isAccessibilityAuthorized {
                Section {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: AccessibilityPermission.systemImageName)
                            .font(.title)
                            .foregroundStyle(Color.effectiveAccent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(AccessibilityPermission.displayName) Required")
                                .font(.headline)
                            Text("Grant \(AccessibilityPermission.displayName) to mirror notification banners.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Grant Access") {
                            Task {
                                let granted = await MediaKeyInterceptor.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                                isAccessibilityAuthorized = granted
                            }
                        }
                    }
                }
            }

            Section {
                Defaults.Toggle(key: .notificationsFromAllApps) {
                    Text("From all apps")
                }
                .disabled(!notificationLiveActivity)

                if !notificationsFromAllApps {
                    if selectedApps.isEmpty {
                        Text("No apps selected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(selectedApps) { app in
                            HStack {
                                appIcon(for: app.bundleID)
                                    .resizable().scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))

                                Text(app.name)
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    allowedApps.remove(app.bundleID)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    Button {
                        chooseApplication()
                    } label: {
                        Label("Add Application…", systemImage: "plus")
                    }
                }
            } header: {
                Text("Apps")
            } footer: {
                if !notificationsFromAllApps {
                    Text("Only selected apps are mirrored. Add applications from your Mac; no preset app list is used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!notificationLiveActivity)
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
        .task {
            isAccessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                isAccessibilityAuthorized = granted
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                isAccessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
            }
        }
        .onChange(of: allowedApps) { _, _ in
            SystemNotificationManager.shared.updateFilter()
        }
        .onChange(of: notificationsFromAllApps) { _, _ in
            SystemNotificationManager.shared.updateFilter()
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["app"]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK else { return }
            let bundleIDs = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            guard !bundleIDs.isEmpty else { return }
            DispatchQueue.main.async {
                allowedApps.formUnion(bundleIDs)
            }
        }
    }
}

/// LaunchServices + `Bundle(url:)` are too slow to repeat for every app on every render.
@MainActor private var displayNameCache: [String: String] = [:]

@MainActor private func displayName(for bundleID: String) -> String {
    if let cached = displayNameCache[bundleID] { return cached }
    let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String }
        ?? bundleID
    displayNameCache[bundleID] = name
    return name
}
