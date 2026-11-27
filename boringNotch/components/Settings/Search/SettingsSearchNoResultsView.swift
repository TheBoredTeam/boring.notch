//
//  SettingsSearchNoResultsView.swift
//  boringNotch
//

import SwiftUI

// Laid out like the same state in macOS System Settings. `ContentUnavailableView.search` is sized
// for a full window and does not fit the 200 pt sidebar.
struct SettingsSearchNoResultsView: View {
    let query: String

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
                .accessibilityHidden(true)
            Text("No Results", comment: "Title shown in the settings sidebar when a search finds nothing.")
            Text(
                "No results for “\(query)”",
                comment: "Shown under “No Results” in the settings sidebar. The placeholder is the text the user searched for."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }
}
