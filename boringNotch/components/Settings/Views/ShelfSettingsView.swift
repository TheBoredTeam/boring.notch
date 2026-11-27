//
//  ShelfSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import SwiftUI

struct ShelfSettingsView: View {
    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection: Bool
    @StateObject private var quickShareService = QuickShareService.shared

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .boringShelf) {
                    Text("Enable shelf")
                }
                .settingsSearchAnchor(SearchKey.enableShelf)
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("Open shelf by default if items are present")
                }
                .settingsSearchAnchor(SearchKey.openByDefault)
                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("Expanded drag detection area")
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                .settingsSearchAnchor(SearchKey.expandedDragDetection)
                Defaults.Toggle(key: .copyOnDrag) {
                    Text("Copy items on drag")
                }
                .settingsSearchAnchor(SearchKey.copyOnDrag)
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Remove from shelf after dragging")
                }
                .settingsSearchAnchor(SearchKey.removeAfterDragging)
                Defaults.Toggle(key: .reverseShelfOrdering) {
                    Text("Keep newer shelf items in front")
                }
                .settingsSearchAnchor(SearchKey.newerItemsInFront)
            } header: {
                Text("General")
            }

            Section {
                Picker("Quick Share Service", selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            Group {
                                if let icon = quickShareService.icon(for: provider.id, size: 16) {
                                    Image(nsImage: icon)
                                        .resizable().scaledToFit()
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            .frame(width: 16, height: 16)
                            .foregroundColor(.accentColor)
                            Text(provider.id)
                        }
                        .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                .settingsSearchAnchor(SearchKey.quickShareService)

                if let selectedProvider = selectedProvider {
                    HStack {
                        Group {
                            if let icon = quickShareService.icon(for: selectedProvider.id, size: 16) {
                                Image(nsImage: icon)
                                    .resizable().scaledToFit()
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .frame(width: 16, height: 16)
                        .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Currently selected: \(selectedProvider.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Files dropped on the shelf will be shared via this service")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("Quick Share")
                }
            } footer: {
                Text("Choose which service to use when sharing files from the shelf. Click the shelf button to select files, or drag files onto it to share immediately.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shelf")
    }
}

extension ShelfSettingsView {
    enum SearchKey: String, SettingsSearchKey {
        case enableShelf
        case openByDefault
        case expandedDragDetection
        case copyOnDrag
        case removeAfterDragging
        case newerItemsInFront
        case quickShareService

        static let tab = SettingsTab.shelf

        var definition: SettingsSearchDefinition<Self> {
            switch self {
            case .enableShelf: .init("Enable shelf", section: "General")
            case .openByDefault: .init("Open shelf by default if items are present", section: "General")
            case .expandedDragDetection: .init("Expanded drag detection area", section: "General")
            case .copyOnDrag: .init("Copy items on drag", section: "General")
            case .removeAfterDragging: .init("Remove from shelf after dragging", section: "General")
            case .newerItemsInFront: .init("Keep newer shelf items in front", section: "General")
            case .quickShareService: .init("Quick Share Service", section: "Quick Share")
            }
        }
    }
}
