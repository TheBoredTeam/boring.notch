//
//  ShelfSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AppKit
import Defaults
import SwiftUI

struct Shelf: View {
    
    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection: Bool
    @Default(.linkedShelfFolderBookmark) var linkedShelfFolderBookmark
    @Default(.linkedShelfRecentItemLimit) var linkedShelfRecentItemLimit
    @Default(.shelfIconSize) var shelfIconSize
    @Default(.shelfTextSize) var shelfTextSize
    @Default(.shelfLabelLineCount) var shelfLabelLineCount
    @Default(.showRecentShelfItemOnHome) var showRecentShelfItemOnHome
    @StateObject private var quickShareService = QuickShareService.shared

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }

    init() {
        Task { await QuickShareService.shared.discoverAvailableProviders() }
    }

    private var linkedFolderURL: URL? {
        guard let data = linkedShelfFolderBookmark else { return nil }
        return Bookmark(data: data).resolvedURL
    }

    private var linkedFolderLabel: String {
        linkedFolderURL?.lastPathComponent ?? "No folder selected"
    }

    private func chooseLinkedFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Linked Folder"
        panel.prompt = "Select"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let bookmark = try Bookmark(url: url)
                linkedShelfFolderBookmark = bookmark.data
                ShelfStateViewModel.shared.refreshLinkedItems()
            } catch {
                print("Failed to create bookmark for linked folder: \(error.localizedDescription)")
            }
        }
    }

    private func clearLinkedFolder() {
        linkedShelfFolderBookmark = nil
        ShelfStateViewModel.shared.refreshLinkedItems()
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
                Defaults.Toggle(key: .showRecentShelfItemOnHome) {
                    Text("Show most recent shelf item on Home view")
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

            } header: {
                HStack {
                    Text("General")
                }
            }

            Section {
                HStack {
                    Text("Linked folder")
                    Spacer()
                    Text(linkedFolderLabel)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Choose Folder") {
                        chooseLinkedFolder()
                    }
                    if linkedShelfFolderBookmark != nil {
                        Button("Clear") {
                            clearLinkedFolder()
                        }
                    }
                }
                Stepper(value: $linkedShelfRecentItemLimit, in: 1...4, step: 1) {
                    Text("Recent items: \(linkedShelfRecentItemLimit)")
                }
                .disabled(linkedShelfFolderBookmark == nil)
            } header: {
                HStack {
                    Text("Linked Folder")
                }
            } footer: {
                Text("Shows the most recent items from the selected folder.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Slider(value: $shelfIconSize, in: 40...96, step: 2) {
                    Text("Icon size - \(shelfIconSize, specifier: "%.0f")")
                }
                Slider(value: $shelfTextSize, in: 10...18, step: 1) {
                    Text("Label text size - \(shelfTextSize, specifier: "%.0f")")
                }
                Stepper(value: $shelfLabelLineCount, in: 1...2, step: 1) {
                    Text("Label rows: \(shelfLabelLineCount)")
                }
            } header: {
                HStack {
                    Text("Appearance")
                }
            }
            
            Section {
                Picker("Quick Share Service", selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            Group {
                                if let icon = quickShareService.icon(for: provider.id, size: 16) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
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
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
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
        .onChange(of: linkedShelfFolderBookmark) {
            ShelfStateViewModel.shared.refreshLinkedItems()
        }
        .onChange(of: linkedShelfRecentItemLimit) {
            ShelfStateViewModel.shared.refreshLinkedItems()
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shelf")
    }
}
