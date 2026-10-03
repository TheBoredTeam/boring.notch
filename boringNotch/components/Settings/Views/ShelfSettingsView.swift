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
    @Default(.boringShelf) var boringShelf: Bool
    @Default(.floatingShelf) var floatingShelf: Bool
    @Default(.floatingShelfShakeTrigger) var floatingShelfShakeTrigger: Bool
    @Default(.floatingShelfShakeSensitivity) var floatingShelfShakeSensitivity
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
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("Open shelf by default if items are present")
                }
                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("Expanded drag detection area")
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    Text("Copy items on drag")
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Remove from shelf after dragging")
                }
                Defaults.Toggle(key: .reverseShelfOrdering) {
                    Text("Keep newer shelf items in front")
                }
            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .floatingShelf) {
                    Text("Enable floating shelf")
                }
                Defaults.Toggle(key: .floatingShelfShakeTrigger) {
                    Text("Open by shaking while dragging")
                }
                .disabled(!floatingShelf)
                Picker("Shake sensitivity", selection: $floatingShelfShakeSensitivity) {
                    ForEach(ShakeSensitivity.allCases) { sensitivity in
                        Text(sensitivity.localizedString).tag(sensitivity)
                    }
                }
                .disabled(!floatingShelf || !floatingShelfShakeTrigger)
                Defaults.Toggle(key: .floatingShelfShiftTrigger) {
                    Text("Open by holding Shift while dragging")
                }
                .disabled(!floatingShelf)
            } header: {
                Text("Floating shelf")
            } footer: {
                Text("Opens a shelf beside the pointer while you drag files or text. The floating shelf shortcut in Shortcuts toggles it anytime, and Escape closes it. Opened from the shortcut, it stays up until you drop a file, share, drag an item out, or choose a menu action, then closes when the pointer leaves.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .disabled(!boringShelf)

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
