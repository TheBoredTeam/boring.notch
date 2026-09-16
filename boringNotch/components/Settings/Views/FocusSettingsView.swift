//
//  FocusSettingsView.swift
//  boringNotch
//
//  Focus timer settings: interval lengths, what happens between phases, and
//  which apps and sites to keep out of the way.
//

import Defaults
import SwiftUI

struct FocusSettingsView: View {
    @Default(.focusTimerEnabled) private var enabled
    @Default(.focusWorkMinutes) private var workMinutes
    @Default(.focusShortBreakMinutes) private var shortBreakMinutes
    @Default(.focusLongBreakMinutes) private var longBreakMinutes
    @Default(.focusIntervalsBeforeLongBreak) private var intervalsBeforeLongBreak
    @Default(.focusBlockedApps) private var blockedApps
    @Default(.focusBlockedSites) private var blockedSites

    @State private var newSite = ""
    @State private var siteError: String?

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .focusTimerEnabled) {
                    Text("Show the focus timer")
                }
            } footer: {
                Text("Adds a Focus tab with a Pomodoro timer. While a session runs, the countdown appears in the closed notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $workMinutes, in: 1...180) {
                    LabeledContent("Focus interval", value: minutes(workMinutes))
                }
                Stepper(value: $shortBreakMinutes, in: 1...60) {
                    LabeledContent("Short break", value: minutes(shortBreakMinutes))
                }
                Stepper(value: $longBreakMinutes, in: 1...120) {
                    LabeledContent("Long break", value: minutes(longBreakMinutes))
                }
                Stepper(value: $intervalsBeforeLongBreak, in: 1...12) {
                    LabeledContent("Long break after", value: intervals(intervalsBeforeLongBreak))
                }
            } header: {
                Text("Intervals")
            } footer: {
                Text("Changing a length mid-session keeps your place in the current interval rather than adding or removing time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            Section {
                Defaults.Toggle(key: .focusAutoStartBreaks) { Text("Start breaks automatically") }
                Defaults.Toggle(key: .focusAutoStartWork) { Text("Start the next focus interval automatically") }
                Defaults.Toggle(key: .focusPlaySound) { Text("Play a sound when an interval ends") }
            } header: {
                Text("Between intervals")
            }
            .disabled(!enabled)

            blockedAppsSection
            blockedSitesSection

            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Blocking is a nudge, not a lock.")
                            .font(.caption.weight(.semibold))
                        Text(
                            """
                            Blocked apps are hidden, not quit, and you can bring them straight back. \
                            Blocked sites are handled per tab: the front tab is sent to a blank page. \
                            Neither survives a determined detour, and neither touches your network settings.
                            """
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text(
                            """
                            Site blocking needs Automation access for each browser, which macOS asks for \
                            the first time it is used. Firefox is not supported — it provides no way for \
                            another app to read the active tab.
                            """
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Focus")
    }

    // MARK: - Apps

    private var blockedAppsSection: some View {
        Section {
            ForEach(DistractionBlocklist.suggestedApps) { app in
                Toggle(isOn: appBinding(app)) {
                    HStack {
                        appIcon(for: app.bundleID)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        Text(appName(for: app.bundleID))
                    }
                }
            }

            Button("Choose an app…") { chooseApp() }
        } header: {
            Text("Block apps")
        } footer: {
            let custom = blockedApps.subtracting(Set(DistractionBlocklist.suggestedApps.map(\.bundleID)))
            if custom.isEmpty {
                Text("Hidden while a focus interval is running. Browsers are never hidden — use Block sites instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(custom.sorted(), id: \.self) { bundleID in
                        HStack {
                            Text(appName(for: bundleID)).font(.caption)
                            Spacer()
                            Button("Remove") { blockedApps.remove(bundleID) }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .disabled(!enabled)
    }

    private func appBinding(_ app: BlockedApp) -> Binding<Bool> {
        Binding(
            get: { blockedApps.contains(app.bundleID) },
            set: { on in
                if on { blockedApps.insert(app.bundleID) } else { blockedApps.remove(app.bundleID) }
            }
        )
    }

    /// Uses the open panel rather than a free-text bundle ID field: the app is
    /// sandboxed, and picking through the panel is both friendlier and the
    /// only way to reliably resolve a bundle identifier.
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = NSLocalizedString("Add", comment: "Open panel button: add the chosen app to the blocklist")

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            guard !DistractionBlocklist.browserBundleIDs.contains(bundleID.lowercased()) else { continue }
            blockedApps.insert(bundleID)
        }
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    // MARK: - Sites

    private var blockedSitesSection: some View {
        Section {
            ForEach(blockedSites.sorted(), id: \.self) { host in
                HStack {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                    Text(host)
                    Spacer()
                    Button("Remove") { blockedSites.remove(host) }
                        .buttonStyle(.link)
                }
            }

            HStack {
                TextField("Add a site, e.g. reddit.com", text: $newSite)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addSite)
                Button("Add", action: addSite)
                    .disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            let missing = DistractionBlocklist.suggestedSites.filter { !blockedSites.contains($0.host) }
            if !missing.isEmpty {
                // One tap per suggestion rather than a "restore defaults"
                // button, so adding one back never silently re-adds the rest.
                WrappingSuggestions(hosts: missing.map(\.host)) { blockedSites.insert($0) }
            }
        } header: {
            Text("Block sites")
        } footer: {
            if let siteError {
                Text(siteError).font(.caption).foregroundStyle(.orange)
            } else {
                Text("Subdomains are included: blocking reddit.com also blocks old.reddit.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!enabled)
    }

    private func addSite() {
        guard let site = BlockedSite(userInput: newSite) else {
            siteError = NSLocalizedString(
                "focus_site_invalid",
                comment: "Shown when the text typed into the blocked-sites field is not a usable host"
            )
            return
        }
        blockedSites.insert(site.host)
        newSite = ""
        siteError = nil
    }

    // MARK: - Formatting

    private func minutes(_ value: Int) -> String {
        String(format: NSLocalizedString("focus_minutes_short", comment: "A duration in minutes, e.g. '25 min'"), value)
    }

    private func intervals(_ value: Int) -> String {
        String(format: NSLocalizedString("focus_intervals_count", comment: "Number of focus intervals, e.g. '4 intervals'"), value)
    }
}

/// A flow of one-tap suggestion chips. `LazyVGrid` with adaptive columns
/// rather than an `HStack`, so a long host name wraps instead of being
/// squeezed or clipped in the settings column.
private struct WrappingSuggestions: View {
    let hosts: [String]
    let onAdd: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(hosts, id: \.self) { host in
                Button {
                    onAdd(host)
                } label: {
                    Label(host, systemImage: "plus")
                        .font(.caption)
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
