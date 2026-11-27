//
//  SettingsSearchKey.swift
//  boringNotch
//

import Foundation

struct SettingsSearchDefinition<Key> {
    // Written exactly as in the view, so it shares the view's translation.
    let title: LocalizedStringResource
    let section: LocalizedStringResource?
    let keywords: [LocalizedStringResource]
    // The control that has to be turned on before this one is shown.
    let revealedBy: Key?

    init(
        _ title: LocalizedStringResource,
        section: LocalizedStringResource? = nil,
        keywords: [LocalizedStringResource] = [],
        revealedBy: Key? = nil
    ) {
        self.title = title
        self.section = section
        self.keywords = keywords
        self.revealedBy = revealedBy
    }
}

// Each settings view declares its searchable controls as an enum next to the controls themselves.
// `CaseIterable` plus an exhaustive `switch` in `definition` means there is no second list to keep in sync.
protocol SettingsSearchKey: CaseIterable, Hashable, RawRepresentable where RawValue == String {
    static var tab: SettingsTab { get }
    var definition: SettingsSearchDefinition<Self> { get }
}

extension SettingsSearchKey {
    var searchID: String {
        "\(Self.tab.rawValue).\(rawValue)"
    }

    static var entries: [SettingsSearchEntry] {
        allCases.map { key in
            let definition = key.definition
            return SettingsSearchEntry(
                id: key.searchID,
                tab: tab,
                title: String(localized: definition.title),
                section: definition.section.map { String(localized: $0) },
                keywords: definition.keywords.map { String(localized: $0) },
                revealedByID: definition.revealedBy?.searchID
            )
        }
    }
}
