//
//  SettingsSearchIndex.swift
//  boringNotch
//

import Foundation

struct SettingsSearchIndex {
    struct Tab {
        let tab: SettingsTab
        let title: String
        let entries: [SettingsSearchEntry]
    }

    let tabs: [Tab]

    var entries: [SettingsSearchEntry] {
        tabs.flatMap(\.entries)
    }
}

extension SettingsSearchIndex {
    static func current() -> SettingsSearchIndex {
        SettingsSearchIndex(tabs: SettingsTab.allCases.map { tab in
            Tab(tab: tab, title: String(localized: tab.title), entries: tab.searchEntries)
        })
    }

    func entry(withID id: String) -> SettingsSearchEntry? {
        entries.first { $0.id == id }
    }
}
