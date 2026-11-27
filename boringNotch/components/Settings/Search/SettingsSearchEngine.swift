//
//  SettingsSearchEngine.swift
//  boringNotch
//

import Foundation

struct SettingsSearchGroup: Identifiable {
    let tab: SettingsTab
    // Empty when only the tab's own name matched.
    let entries: [SettingsSearchEntry]

    var id: SettingsTab { tab }
}

enum SettingsSearchEngine {
    // Weakest first: `Comparable` follows the order of the cases.
    private enum Rank: Comparable {
        case tab
        case section
        case keyword
        case titleContains
        case titleWordPrefix
        case titlePrefix
    }

    private struct SearchText {
        let folded: String
        let words: [String]

        init(_ text: String) {
            folded = text.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: nil
            )
            words = folded
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }
    }

    static func search(_ query: String, in index: SettingsSearchIndex) -> [SettingsSearchGroup] {
        let tokens = SearchText(query).words
        guard !tokens.isEmpty else { return [] }

        let ranked = index.tabs.enumerated().compactMap { offset, tab -> (group: SettingsSearchGroup, best: Rank, offset: Int)? in
            let tabText = SearchText(tab.title)
            let matches = rankedEntries(in: tab, tabText: tabText, tokens: tokens)
            let tabNameMatches = tokens.allSatisfy { tabText.folded.contains($0) }
            guard !matches.isEmpty || tabNameMatches else { return nil }

            let group = SettingsSearchGroup(tab: tab.tab, entries: matches.map(\.entry))
            return (group, matches.first?.rank ?? .tab, offset)
        }

        return ranked
            .sorted { $0.best != $1.best ? $0.best > $1.best : $0.offset < $1.offset }
            .map(\.group)
    }

    private static func rankedEntries(
        in tab: SettingsSearchIndex.Tab,
        tabText: SearchText,
        tokens: [String]
    ) -> [(entry: SettingsSearchEntry, rank: Rank)] {
        tab.entries.enumerated()
            .compactMap { offset, entry -> (entry: SettingsSearchEntry, rank: Rank, offset: Int)? in
                guard let rank = rank(of: entry, tabText: tabText, tokens: tokens) else { return nil }
                return (entry, rank, offset)
            }
            // Equal ranks keep the order the settings have on screen.
            .sorted { $0.rank != $1.rank ? $0.rank > $1.rank : $0.offset < $1.offset }
            .map { ($0.entry, $0.rank) }
    }

    // An entry is ranked by its weakest word, so "osd percent" does not rank like a full title match.
    private static func rank(of entry: SettingsSearchEntry, tabText: SearchText, tokens: [String]) -> Rank? {
        let title = SearchText(entry.title)
        let keywords = entry.keywords.map(SearchText.init)
        let section = entry.section.map(SearchText.init)

        var weakest = Rank.titlePrefix
        for token in tokens {
            let tokenRank: Rank
            if title.words.contains(where: { $0.hasPrefix(token) }) {
                tokenRank = .titleWordPrefix
            } else if title.folded.contains(token) {
                tokenRank = .titleContains
            } else if keywords.contains(where: { $0.folded.contains(token) }) {
                tokenRank = .keyword
            } else if section?.folded.contains(token) == true {
                tokenRank = .section
            } else if tabText.folded.contains(token) {
                tokenRank = .tab
            } else {
                return nil
            }
            weakest = min(weakest, tokenRank)
        }

        let startsWithQuery = title.words.joined(separator: " ").hasPrefix(tokens.joined(separator: " "))
        return startsWithQuery ? .titlePrefix : weakest
    }
}
