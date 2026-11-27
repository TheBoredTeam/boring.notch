//
//  SettingsSearchEntry.swift
//  boringNotch
//

import Foundation

struct SettingsSearchEntry: Identifiable, Equatable {
    let id: String
    let tab: SettingsTab
    let title: String
    let section: String?
    let keywords: [String]
    let revealedByID: String?

    init(
        id: String,
        tab: SettingsTab,
        title: String,
        section: String? = nil,
        keywords: [String] = [],
        revealedByID: String? = nil
    ) {
        self.id = id
        self.tab = tab
        self.title = title
        self.section = section
        self.keywords = keywords
        self.revealedByID = revealedByID
    }
}
