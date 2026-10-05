//
//  HUDModulesSettings.swift
//  boringNotch
//
//  Settings panes for the optional Developer HUD and GitHub HUD modules.
//

import AppKit
import Defaults
import SwiftUI

struct DeveloperHUDSettings: View {
    @Default(.developerHUDEnabled) var enabled
    @Default(.devHUDProjectBookmarks) var bookmarks

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .developerHUDEnabled) {
                    Text("Enable Developer HUD")
                }
                Text("Adds a Dev tab to the open notch with Git, system and environment status. Nothing runs while it is disabled or not on screen.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Developer HUD") }

            Section {
                if bookmarks.isEmpty {
                    Text("No projects added").foregroundStyle(.secondary)
                }
                ForEach(Array(bookmarks.enumerated()), id: \.offset) { index, bookmark in
                    HStack {
                        Label(DeveloperHUDManager.displayName(for: bookmark), systemImage: "folder")
                        Spacer()
                        Button(role: .destructive) { bookmarks.remove(at: index) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add Project Folder…", action: addProject)
                Text("macOS sandboxing means you grant access to each project folder once. With Accessibility enabled and several projects added, the HUD follows the project in your frontmost editor window.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Projects") }
            .disabled(!enabled)

            Section {
                Defaults.Toggle("Git status & branch", key: .devHUDShowGit)
                Defaults.Toggle("Last commit", key: .devHUDShowLastCommit)
                Defaults.Toggle("CPU & memory", key: .devHUDShowSystem)
                Defaults.Toggle("Build status", key: .devHUDShowBuild)
                Defaults.Toggle("Dev servers (localhost ports)", key: .devHUDShowServers)
                Defaults.Toggle("Running terminal tasks", key: .devHUDShowTasks)
            } header: { Text("Show") }
            .disabled(!enabled)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Developer HUD")
        .onChange(of: enabled) { _, on in
            if !on && BoringViewCoordinator.shared.currentView == .developer { BoringViewCoordinator.shared.currentView = .home }
        }
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = DeveloperHUDManager.bookmark(for: url) else { return }
        bookmarks.append(data)
    }
}

struct GitHubHUDSettings: View {
    @Default(.githubHUDEnabled) var enabled
    @Default(.githubRefreshMinutes) var refreshMinutes
    @State private var tokenInput = ""
    @State private var hasToken = GitHubAuthService.hasToken
    @State private var message: String?
    @State private var working = false
    @ObservedObject private var manager = GitHubHUDManager.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .githubHUDEnabled) { Text("Enable GitHub HUD") }
                Text("Adds a GitHub tab to the open notch. Data is fetched only while the tab is visible and cached between refreshes.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("GitHub HUD") }

            Section {
                if hasToken {
                    HStack {
                        Label(manager.snapshot.map { "Signed in as @\($0.user.login)" } ?? "Token saved in Keychain",
                              systemImage: "checkmark.shield")
                        Spacer()
                        Button("Remove Token", role: .destructive) {
                            GitHubAuthService.deleteToken()
                            hasToken = false
                            message = nil
                            Task { await manager.credentialsChanged() }
                        }
                    }
                } else {
                    SecureField("Personal access token", text: $tokenInput)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save to Keychain") { save() }
                            .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty || working)
                        Button("Create Token…") {
                            NSWorkspace.shared.open(URL(string: "https://github.com/settings/tokens/new?scopes=notifications,repo,read:user&description=boringNotch")!)
                        }
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                Text("Use a classic token with notifications, repo and read:user scopes (fine-grained tokens cannot read notifications). The token is stored only in the macOS Keychain and sent only to api.github.com.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Authentication") }
            .disabled(!enabled)

            Section {
                Defaults.Toggle("Notifications", key: .githubShowNotifications)
                Defaults.Toggle("Assigned pull requests", key: .githubShowPullRequests)
                Defaults.Toggle("Review requests", key: .githubShowReviewRequests)
                Defaults.Toggle("Assigned issues", key: .githubShowIssues)
                Defaults.Toggle("Recent activity & commits", key: .githubShowActivity)
                Defaults.Toggle("GitHub Actions status", key: .githubShowActions)
                Defaults.Toggle("Contribution summary", key: .githubShowContributions)
            } header: { Text("Show") }
            .disabled(!enabled)

            Section {
                Picker("Refresh every", selection: $refreshMinutes) {
                    ForEach([2, 5, 10, 15, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                }
            } header: { Text("Refresh") }
            .disabled(!enabled)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("GitHub HUD")
        .onChange(of: enabled) { _, on in
            if !on && BoringViewCoordinator.shared.currentView == .github { BoringViewCoordinator.shared.currentView = .home }
        }
    }

    private func save() {
        working = true
        let token = tokenInput
        guard GitHubAuthService.saveToken(token) else {
            message = "Couldn't save to the Keychain."
            working = false
            return
        }
        tokenInput = ""
        hasToken = true
        message = "Saved. Loading…"
        Task {
            await manager.credentialsChanged()
            working = false
            message = nil
        }
    }
}
