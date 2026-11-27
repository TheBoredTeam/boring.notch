//
//  SettingsSearchResultRows.swift
//  boringNotch
//

import SwiftUI

struct SettingsSearchResultRows: View {
    let groups: [SettingsSearchGroup]
    let index: SettingsSearchIndex

    var body: some View {
        ForEach(groups) { group in
            // The tab row is always there, so a tab found only by its name can still be opened.
            SettingsTabLabel(tab: group.tab)
                .tag(SettingsSidebarItem.tab(group.tab))
                .id(SettingsSidebarItem.tab(group.tab))
            ForEach(group.entries) { entry in
                entryRow(entry)
                    .tag(SettingsSidebarItem.entry(entry.id))
            }
        }
    }

    private func entryRow(_ entry: SettingsSearchEntry) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.title)
            if let detail = detail(for: entry) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(2)
        .padding(.leading, 24)
        .accessibilityElement(children: .combine)
    }

    private func detail(for entry: SettingsSearchEntry) -> String? {
        if let revealedByID = entry.revealedByID, let parent = index.entry(withID: revealedByID) {
            return String(
                localized: "Requires \(parent.title)",
                comment: "Shown under a settings search result. The placeholder is the name of the setting that must be turned on first."
            )
        }
        return entry.section
    }
}
