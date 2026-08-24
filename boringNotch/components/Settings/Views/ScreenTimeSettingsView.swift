//
//  ScreenTimeSettingsView.swift
//  boringNotch
//
//  Settings pane for the Screen Time widget. All user-facing strings are SwiftUI
//  `Text` literals so they are extracted into Localizable.xcstrings for translation.
//

import Defaults
import SwiftUI

struct ScreenTimeSettings: View {
    @Default(.screenTimeEnabled) var enabled
    @Default(.screenTimeResetHour) var resetHour
    @Default(.screenTimeResetMinute) var resetMinute
    @Default(.screenTimeRetentionDays) var retentionDays
    @Default(.screenTimeIgnoredApps) var ignoredApps
    @Default(.screenTimeCategoryOverrides) var categoryOverrides
    @Default(.screenTimeCategoryColors) var categoryColors

    private var resolver: CategoryResolver { CategoryResolver(overrides: categoryOverrides) }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func appName(for bundleID: String) -> String {
        runningApps.first(where: { $0.bundleIdentifier == bundleID })?.localizedName ?? bundleID
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .screenTimeEnabled) { Text("Enable Screen Time") }
                HStack {
                    Text("Daily reset")
                    Spacer()
                    Picker("", selection: $resetHour) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 64)
                    Text(verbatim: ":")
                    Picker("", selection: $resetMinute) {
                        ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 64)
                }
                Stepper(value: $retentionDays, in: 1...365) {
                    Text("Keep history for \(retentionDays) days")
                }
            } header: {
                Text("General")
            } footer: {
                Text("Usage is tracked locally by following the frontmost app while Boring Notch is running. No data leaves your Mac.")
            }
            .disabled(!enabled)

            Section {
                if ignoredApps.isEmpty {
                    Text("No ignored apps").foregroundStyle(.secondary)
                } else {
                    ForEach(ignoredApps, id: \.self) { bundleID in
                        HStack {
                            AppIcon(for: bundleID).resizable().frame(width: 16, height: 16)
                            Text(verbatim: appName(for: bundleID))
                            Spacer()
                            Button(role: .destructive) {
                                ignoredApps.removeAll { $0 == bundleID }
                            } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Menu {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        if let bid = app.bundleIdentifier, !ignoredApps.contains(bid) {
                            Button(app.localizedName ?? bid) { ignoredApps.append(bid) }
                        }
                    }
                } label: {
                    Text("Add app to ignore list")
                }
            } header: {
                Text("Ignored Apps")
            } footer: {
                Text("Ignored apps are excluded from totals and the app-switch count.")
            }
            .disabled(!enabled)

            Section {
                ForEach(resolver.categories) { category in
                    HStack {
                        ColorPicker(selection: colorBinding(for: category), supportsOpacity: false) {
                            categoryLabel(category)
                        }
                        if categoryColors[category.id] != nil {
                            Button { categoryColors[category.id] = nil } label: { Text("Reset") }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text("Category Colors")
            }
            .disabled(!enabled)

            Section {
                ForEach(runningApps, id: \.bundleIdentifier) { app in
                    if let bid = app.bundleIdentifier {
                        Picker(selection: categoryBinding(for: bid)) {
                            ForEach(resolver.categories) { cat in
                                categoryLabel(cat).tag(cat.id)
                            }
                        } label: {
                            HStack {
                                AppIcon(for: bid).resizable().frame(width: 16, height: 16)
                                Text(verbatim: app.localizedName ?? bid)
                            }
                        }
                    }
                }
            } header: {
                Text("App Categories")
            } footer: {
                Text("Reassign a running app to a different category. Changes are remembered.")
            }
            .disabled(!enabled)
        }
    }

    /// Localized category name as literal `Text` so the String Catalog extracts it.
    private func categoryLabel(_ category: AppCategory) -> Text {
        switch category.id {
        case "development": return Text("Development")
        case "communication": return Text("Communication")
        case "social": return Text("Social")
        case "browsing": return Text("Browsing")
        case "entertainment": return Text("Entertainment")
        case "productivity": return Text("Productivity")
        case "design": return Text("Design")
        case "utilities": return Text("Utilities")
        default: return Text("Other")
        }
    }

    private func colorBinding(for category: AppCategory) -> Binding<Color> {
        Binding(
            get: { Color(stHex: categoryColors[category.id] ?? category.colorHex) },
            set: { categoryColors[category.id] = $0.stHexString() }
        )
    }

    private func categoryBinding(for bundleID: String) -> Binding<String> {
        Binding(
            get: { resolver.category(for: bundleID).id },
            set: { categoryOverrides[bundleID] = $0 }
        )
    }
}
