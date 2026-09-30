//
//  AboutView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import Sparkle
import SwiftUI

struct AboutView: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow

    /// The exact version this build reports, in the format the bug report
    /// form's validator recognizes (see .github/scripts/validate-issue-version.js).
    private var reportVersion: String {
        let version = Bundle.main.releaseVersionNumber ?? "unknown"
        let build = Bundle.main.buildVersionNumber ?? "unknown"
        let channel = UpdateChannel.bundled
        let channelSuffix = channel == .stable ? "" : ", \(channel.rawValue) channel"
        return "\(version) (build \(build)\(channelSuffix))"
    }

    /// Opens the bug report form with the version fields prefilled via the
    /// issue form query parameter API. Keys must match the form field ids;
    /// renaming the template or its version fields breaks shipped apps.
    private var bugReportURL: URL? {
        var components = URLComponents(string: "https://github.com/reesoousa/boring.notch/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "template", value: "1-bug-report-form.yml"),
            URLQueryItem(name: "version", value: reportVersion),
            URLQueryItem(
                name: "operating-system",
                value: ProcessInfo.processInfo.operatingSystemVersionString
            ),
        ]
        return components?.url
    }

    var body: some View {
        Form {
            Section {
                appHeader
            }

            UpdaterSettingsView(updater: updaterController.updater)

            Section {
                creditRow(
                    title: "boringCode",
                    detail: "Renan Sousa (@reesoousa)",
                    systemImage: "person.crop.circle",
                    url: "https://github.com/reesoousa"
                )
                creditRow(
                    title: "Boring Notch",
                    detail: String(localized: "TheBoredTeam — the base of the app and its design"),
                    systemImage: "rectangle.topthird.inset.filled",
                    url: "https://github.com/TheBoredTeam/boring.notch"
                )
                creditRow(
                    title: "Open Island",
                    detail: String(localized: "Octane0411 — reference for the AI agents integration"),
                    systemImage: "sparkles.rectangle.stack",
                    url: "https://github.com/Octane0411/open-vibe-island"
                )
            } header: {
                Text("Credits")
            } footer: {
                Text("Open source under the GPL-3.0 license, like the projects it's based on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        if let url = bugReportURL {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "exclamationmark.bubble")
                                .font(.system(size: 15, weight: .medium))
                                .frame(height: 18)
                            Text("Report a Bug")
                        }
                        .contentShape(Rectangle())
                    }
                    .help("Open a bug report with your version filled in automatically")
                    Button {
                        if let url = URL(string: "https://github.com/reesoousa/boring.notch") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable().scaledToFit()
                                .frame(width: 18, height: 18)
                                .foregroundStyle(.primary)
                            Text("GitHub")
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .toolbar {
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .navigationTitle("About")
    }

    /// Cabeçalho no padrão "Sobre este app" da Apple: ícone grande, nome, versão.
    private var appHeader: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text("boringCode")
                .font(.system(size: 22, weight: .semibold))
            Text("Version \(Bundle.main.releaseVersionNumber ?? "–") (\(BoringCodeRelease.name))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .onTapGesture { withAnimation { showBuildNumber.toggle() } }
            if showBuildNumber {
                Text("Build \(Bundle.main.buildVersionNumber ?? "–")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text("Made for not-so-boring people.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func creditRow(title: String, detail: String, systemImage: String, url: String) -> some View {
        Button {
            if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(url)
    }
}

/// Nome da versão do boringCode (cada versão ganha um apelido, como no Boring Notch).
enum BoringCodeRelease {
    static let name = "Astronaut Cat 🐱🚀"
}
