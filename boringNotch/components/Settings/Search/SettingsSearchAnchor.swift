//
//  SettingsSearchAnchor.swift
//  boringNotch
//

import SwiftUI

// The anchors that are on screen. A setting hidden behind a toggle is not in this set,
// which is how search knows to point at the toggle instead.
struct SettingsSearchAnchorIDsKey: PreferenceKey {
    static let defaultValue: Set<String> = []

    static func reduce(value: inout Set<String>, nextValue: () -> Set<String>) {
        value.formUnion(nextValue())
    }
}

private struct SettingsSearchHighlightKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var settingsSearchHighlightedID: String? {
        get { self[SettingsSearchHighlightKey.self] }
        set { self[SettingsSearchHighlightKey.self] = newValue }
    }
}

private struct SettingsSearchAnchor: ViewModifier {
    let id: String
    @Environment(\.settingsSearchHighlightedID) private var highlightedID

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.effectiveAccent.opacity(highlightedID == id ? 0.25 : 0))
                    .padding(.horizontal, -6)
                    .padding(.vertical, -4)
            }
            .id(id)
            .preference(key: SettingsSearchAnchorIDsKey.self, value: [id])
    }
}

extension View {
    func settingsSearchAnchor<Key: SettingsSearchKey>(_ key: Key) -> some View {
        modifier(SettingsSearchAnchor(id: key.searchID))
    }
}
