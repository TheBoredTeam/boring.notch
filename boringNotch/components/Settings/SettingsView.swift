//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var searchText = ""
    @State private var sidebarSelection: SettingsSidebarItem? = .tab(.general)
    @State private var searchIndex = SettingsSearchIndex.current()
    @State private var searchFocusRequest = 0
    @FocusState private var isSidebarFocused: Bool
    @State private var visibleSearchAnchorIDs: Set<String> = []
    @State private var highlightedSearchID: String?
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?
    let camera: CameraModel

    init(updaterController: SPUStandardUpdaterController? = nil, camera: CameraModel) {
        self.updaterController = updaterController
        self.camera = camera
    }

    var body: some View {
        NavigationSplitView {
            ScrollViewReader { proxy in
                // One list for both tabs and search results, so the sidebar is not rebuilt while typing.
                List(selection: $sidebarSelection) {
                    if isSearching {
                        SettingsSearchResultRows(groups: searchGroups, index: searchIndex)
                    } else {
                        ForEach(SettingsTab.allCases) { tab in
                            SettingsTabLabel(tab: tab)
                                .tag(SettingsSidebarItem.tab(tab))
                                .id(SettingsSidebarItem.tab(tab))
                        }
                    }
                }
                .onChange(of: searchText) {
                    // The list keeps its old scroll position when its rows change, which can leave
                    // the first rows out of view.
                    if let firstTab = isSearching ? searchGroups.first?.tab : SettingsTab.allCases.first {
                        proxy.scrollTo(SettingsSidebarItem.tab(firstTab), anchor: .top)
                    }
                }
            }
            .overlay {
                if isSearching && searchGroups.isEmpty {
                    SettingsSearchNoResultsView(query: searchText.trimmingCharacters(in: .whitespaces))
                }
            }
            .focused($isSidebarFocused)
            .safeAreaInset(edge: .top, spacing: 8) {
                SettingsSearchField(
                    text: $searchText,
                    focusRequest: searchFocusRequest,
                    onMoveToResults: moveToFirstSearchResult
                )
                .controlSize(.large)
                .padding(.horizontal, 8)
            }
            .onAppear {
                // Arrow keys move between tabs when the window opens, as they did before the search field.
                isSidebarFocused = true
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            ScrollViewReader { proxy in
                Group {
                    switch selectedTab {
                    case .general:
                        GeneralSettings()
                    case .notch:
                        NotchSettingsView()
                    case .appearance:
                        AppearanceSettingsView()
                    case .media:
                        MediaSettingsView()
                    case .notifications:
                        NotificationSettingsView()
                    case .calendar:
                        CalendarSettings()
                    case .osd:
                        OSDSettings()
                    case .battery:
                        BatterySettingsView()
                    case .shelf:
                        ShelfSettingsView()
                    case .mirror:
                        WebcamSettingsView(camera: camera)
                    case .shortcuts:
                        ShortcutsSettingsView()
                    case .about:
                        if let controller = updaterController {
                            AboutView(updaterController: controller)
                        } else {
                            // Fallback with a default controller
                            AboutView(
                                updaterController: SPUStandardUpdaterController(
                                    startingUpdater: false, updaterDelegate: nil,
                                    userDriverDelegate: nil))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.settingsSearchHighlightedID, highlightedSearchID)
                .onPreferenceChange(SettingsSearchAnchorIDsKey.self) { visibleSearchAnchorIDs = $0 }
                .task(id: searchRevealTargetID) {
                    await revealSearchTarget(with: proxy)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background {
            // The app has no Find menu item, so ⌘F is handled here.
            Button("Search") {
                searchFocusRequest += 1
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
        }
        .onChange(of: sidebarSelection) {
            openSidebarSelection()
        }
        .onChange(of: isSearching) {
            if !isSearching {
                sidebarSelection = .tab(selectedTab)
            }
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: .accentColorChanged)) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var searchGroups: [SettingsSearchGroup] {
        SettingsSearchEngine.search(searchText, in: searchIndex)
    }

    // The selected result's own row, or the toggle that reveals it while the row is hidden.
    private var searchRevealTargetID: String? {
        guard case .entry(let id) = sidebarSelection else { return nil }
        var entry = searchIndex.entry(withID: id)
        while let current = entry {
            if visibleSearchAnchorIDs.contains(current.id) { return current.id }
            entry = current.revealedByID.flatMap(searchIndex.entry(withID:))
        }
        return nil
    }

    private func revealSearchTarget(with proxy: ScrollViewProxy) async {
        highlightedSearchID = searchRevealTargetID
        guard let target = searchRevealTargetID else { return }
        withAnimation {
            proxy.scrollTo(target, anchor: .center)
        }
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }
        withAnimation {
            highlightedSearchID = nil
        }
    }

    private func moveToFirstSearchResult() {
        guard let first = searchGroups.first else { return }
        sidebarSelection = first.entries.first.map { .entry($0.id) } ?? .tab(first.tab)
        isSidebarFocused = true
    }

    private func openSidebarSelection() {
        switch sidebarSelection {
        case .tab(let tab):
            selectedTab = tab
        case .entry(let id):
            if let entry = searchIndex.entry(withID: id) {
                selectedTab = entry.tab
            }
        case nil:
            // The tab list always shows which tab is open.
            if !isSearching {
                sidebarSelection = .tab(selectedTab)
            }
        }
    }
}
