//
//  MenuBarItemsView.swift
//  boringNotch
//

import AppKit
import CoreGraphics
import Darwin
import Defaults
import ScreenCaptureKit
import SwiftUI

private enum MenuBarItemLayoutReconciler {
    private struct Identity: Hashable {
        let owner: String
        let accessibilityIdentifier: String
        let childIndex: String
    }

    static func order(
        storedIDs: [String],
        currentItems: [MenuBarItemDescriptor]
    ) -> [String] {
        reconcile(storedIDs: storedIDs, currentItems: currentItems)
            + missingCurrentIDs(storedIDs: storedIDs, currentItems: currentItems)
    }

    static func hiddenIDs(
        storedIDs: [String],
        currentItems: [MenuBarItemDescriptor]
    ) -> [String] {
        reconcile(storedIDs: storedIDs, currentItems: currentItems)
    }

    private static func reconcile(
        storedIDs: [String],
        currentItems: [MenuBarItemDescriptor]
    ) -> [String] {
        let currentIDs = Set(currentItems.map(\.id))
        var currentByIdentity: [Identity: String] = [:]
        for item in currentItems {
            if let identity = identity(fromCurrentID: item.id),
               currentByIdentity[identity] == nil {
                currentByIdentity[identity] = item.id
            }
        }
        var result: [String] = []
        var insertedIDs = Set<String>()

        for storedID in storedIDs {
            let resolvedID: String?
            if currentIDs.contains(storedID) {
                resolvedID = storedID
            } else if let storedIdentity = identity(fromCurrentID: storedID)
                ?? identity(fromLegacyID: storedID) {
                resolvedID = currentByIdentity[storedIdentity]
            } else {
                resolvedID = nil
            }

            if let resolvedID, insertedIDs.insert(resolvedID).inserted {
                result.append(resolvedID)
            }
        }
        return result
    }

    private static func missingCurrentIDs(
        storedIDs: [String],
        currentItems: [MenuBarItemDescriptor]
    ) -> [String] {
        let reconciledIDs = Set(
            reconcile(storedIDs: storedIDs, currentItems: currentItems)
        )
        return currentItems.map(\.id).filter { !reconciledIDs.contains($0) }
    }

    private static func identity(fromCurrentID identifier: String) -> Identity? {
        let components = identifier.split(
            separator: "|",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard components.count == 4, components[0] == "v2" else { return nil }
        return Identity(
            owner: components[1],
            accessibilityIdentifier: components[2],
            childIndex: components[2].isEmpty ? components[3] : ""
        )
    }

    private static func identity(fromLegacyID identifier: String) -> Identity? {
        let components = identifier.split(
            separator: "|",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard components.count >= 5,
              !components[0].hasPrefix("pid:") else { return nil }
        return Identity(
            owner: components[0],
            accessibilityIdentifier: components[1],
            childIndex: components[1].isEmpty ? components[components.count - 1] : ""
        )
    }
}

@MainActor
final class MenuBarItemsViewModel: ObservableObject {
    static let shared = MenuBarItemsViewModel()

    @Published private(set) var items: [MenuBarItemDescriptor] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshingPreviews = false
    @Published private(set) var isActivating = false
    @Published private(set) var accessibilityAuthorized = false
    @Published private(set) var previewImages: [String: NSImage] = [:]
    @Published private(set) var appIcons: [String: NSImage] = [:]
    @Published private(set) var hasCompletedInitialPreviewLoad = false
    @Published var errorMessage: String?

    private var refreshGeneration = 0
    private var attemptedAppIconBundleIdentifiers = Set<String>()
    private var loadedPreviewMode: Bool?
    private var loadedScreenCaptureAuthorized: Bool?

    func hasReusableContent(capturePreviews: Bool) -> Bool {
        guard hasCompletedInitialPreviewLoad,
              loadedPreviewMode == capturePreviews,
              accessibilityAuthorized else { return false }
        guard capturePreviews else { return true }
        return loadedScreenCaptureAuthorized == CGPreflightScreenCaptureAccess()
    }

    func load(
        capturePreviews: Bool = false,
        showPreviewActivity: Bool = true
    ) async {
        guard !isLoading else { return }
        isLoading = true
        refreshGeneration += 1
        let generation = refreshGeneration
        defer {
            if generation == refreshGeneration {
                isLoading = false
                isRefreshingPreviews = false
            }
        }

        let response = await XPCHelperClient.shared.menuBarItems()
        guard generation == refreshGeneration else { return }
        loadAppIcons(for: response.items)
        let screenCaptureAuthorized = capturePreviews
            && CGPreflightScreenCaptureAccess()

        // On the first load, publish the descriptors before capturing pixels.
        // Their frames define the final tile widths, so the loading placeholders
        // can occupy exactly the same geometry as the completed previews.
        if !hasCompletedInitialPreviewLoad {
            items = response.items
            accessibilityAuthorized = response.accessibilityAuthorized
            errorMessage = response.errorMessage
        }

        guard response.accessibilityAuthorized, !response.items.isEmpty else {
            items = response.items
            accessibilityAuthorized = response.accessibilityAuthorized
            errorMessage = response.errorMessage
            previewImages = [:]
            hasCompletedInitialPreviewLoad = true
            loadedPreviewMode = capturePreviews
            loadedScreenCaptureAuthorized = capturePreviews
                ? screenCaptureAuthorized
                : nil
            return
        }

        guard capturePreviews else {
            items = response.items
            accessibilityAuthorized = response.accessibilityAuthorized
            errorMessage = response.errorMessage
            previewImages = [:]
            hasCompletedInitialPreviewLoad = true
            loadedPreviewMode = false
            loadedScreenCaptureAuthorized = nil
            return
        }

        if showPreviewActivity {
            isRefreshingPreviews = true
        }

        let refreshedImages: [String: NSImage]
        if screenCaptureAuthorized {
            refreshedImages = await MenuBarItemPreviewProvider.shared.capturePreviews(
                for: response.items
            )
        } else {
            refreshedImages = [:]
        }
        guard generation == refreshGeneration else { return }

        // Publish the newly discovered list and its previews together. This
        // avoids briefly showing an app icon before the first live frame and
        // lets newly created status items appear without a manual refresh.
        items = response.items
        accessibilityAuthorized = response.accessibilityAuthorized
        errorMessage = response.errorMessage
        previewImages = refreshedImages
        hasCompletedInitialPreviewLoad = true
        loadedPreviewMode = true
        loadedScreenCaptureAuthorized = screenCaptureAuthorized
    }

    func refreshLiveItems() async {
        await load(capturePreviews: true, showPreviewActivity: false)
    }

    private func loadAppIcons(for items: [MenuBarItemDescriptor]) {
        let currentIdentifiers = Set(items.compactMap(\.bundleIdentifier))
        let retainedIcons = appIcons.filter { currentIdentifiers.contains($0.key) }
        if retainedIcons.count != appIcons.count {
            appIcons = retainedIcons
        }
        attemptedAppIconBundleIdentifiers.formIntersection(currentIdentifiers)

        let identifiersToLoad = currentIdentifiers
            .subtracting(attemptedAppIconBundleIdentifiers)
        guard !identifiersToLoad.isEmpty else { return }
        attemptedAppIconBundleIdentifiers.formUnion(identifiersToLoad)

        Task { [weak self] in
            let icons = await AppIconCache.shared.icons(
                for: Array(identifiersToLoad)
            )
            guard !Task.isCancelled, let self else { return }
            var mergedIcons = self.appIcons
            mergedIcons.merge(icons) { _, loaded in loaded }
            self.appIcons = mergedIcons
        }
    }

    func openMenu(
        _ item: MenuBarItemDescriptor,
        viewModel: BoringViewModel,
        anchorWindow: NSWindow?
    ) async {
        guard !isActivating else { return }
        isActivating = true
        errorMessage = nil

        let response = await XPCHelperClient.shared.menu(for: item)
        isActivating = false

        if response.isSupported {
            MenuBarMenuPresenter.shared.present(
                entries: response.entries,
                for: item,
                viewModel: viewModel,
                anchorWindow: anchorWindow
            )
        } else if response.originalMenuPresented {
            // Custom popovers cannot be mirrored safely. AXPress has already
            // opened the original UI, so reveal it by closing the notch.
            viewModel.close()
        } else {
            showMenuBarAccessAlert(response.errorMessage)
        }
    }

    private func showMenuBarAccessAlert(_ message: String?) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Couldn’t open menu bar item")
        alert.informativeText = message
            ?? String(localized: "Please refresh the list and try again.")
        alert.alertStyle = .warning
        alert.runModal()
    }
}

struct MenuBarItemsView: View {
    let isActive: Bool
    @EnvironmentObject private var notchViewModel: BoringViewModel
    @ObservedObject private var model = MenuBarItemsViewModel.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @State private var scrollTargetID: String?
    @State private var scrollIndex = 0
    @State private var skeletonIsBright = false
    @State private var isDraggingStrip = false
    @Default(.menuBarLivePreviews) private var livePreviews
    @Default(.menuBarPreviewRefreshInterval) private var previewRefreshInterval
    @Default(.menuBarItemDisplaySize) private var itemDisplaySize
    @Default(.menuBarItemShowLabels) private var showItemLabels
    @Default(.menuBarHiddenItemIDs) private var hiddenItemIDs
    @Default(.menuBarItemOrder) private var itemOrder

    private var visibleItems: [MenuBarItemDescriptor] {
        // Resolve legacy or changed status-item IDs before the first real
        // list frame is rendered. Previously the list first appeared using
        // the raw stored IDs, then reconcileLayout() changed its order and
        // visibility on the following render, producing a short horizontal
        // jump immediately after the skeleton disappeared.
        let effectiveHiddenIDs = Set(
            MenuBarItemLayoutReconciler.hiddenIDs(
                storedIDs: hiddenItemIDs,
                currentItems: model.items
            )
        )
        let effectiveOrder = MenuBarItemLayoutReconciler.order(
            storedIDs: itemOrder,
            currentItems: model.items
        )
        var orderByID: [String: Int] = [:]
        for (index, identifier) in effectiveOrder.enumerated() where orderByID[identifier] == nil {
            orderByID[identifier] = index
        }

        return model.items
            .filter { !effectiveHiddenIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsOrder = orderByID[lhs.id] ?? Int.max
                let rhsOrder = orderByID[rhs.id] ?? Int.max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var livePreviewTaskID: String {
        "\(isActive)-\(livePreviews)-\(previewRefreshInterval)"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Menu Bar Items")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
//                    Text(livePreviews ? "Live status item previews" : "Status items exposed by running apps")
//                        .font(.caption2)
//                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 6)

            Group {
                if !model.hasCompletedInitialPreviewLoad && model.items.isEmpty {
                    skeletonStrip
                } else if !model.accessibilityAuthorized {
                    permissionView
                } else if let errorMessage = model.errorMessage {
                    statusView(icon: "exclamationmark.triangle", message: errorMessage)
                } else if model.items.isEmpty {
                    statusView(
                        icon: "checkmark.circle",
                        message: String(localized: "No accessible menu bar items found")
                    )
                } else if visibleItems.isEmpty {
                    statusView(
                        icon: "eye.slash",
                        message: String(localized: "All menu bar items are hidden in Settings")
                    )
                } else {
                    itemStrip
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transaction(value: model.hasCompletedInitialPreviewLoad) { transaction in
                // Loading completion swaps the skeleton for the real strip.
                // It is a data update, not a tab transition, so it must not
                // inherit an in-flight animation transaction.
                transaction.animation = nil
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .task(id: livePreviewTaskID) {
            guard isActive else { return }
            // Re-entering the tab should be a pure view switch. Reuse the
            // shared snapshot instead of immediately rediscovering and
            // recapturing every status item, which invalidated the whole menu
            // content subtree on every click.
            if !model.hasReusableContent(capturePreviews: livePreviews) {
                await model.load(capturePreviews: livePreviews)
            }
            reconcileLayout()
            guard livePreviews, model.accessibilityAuthorized else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        for: .seconds(max(0.25, previewRefreshInterval))
                    )
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await model.refreshLiveItems()
            }
        }
        .onChange(of: model.items.map(\.id)) {
            reconcileLayout()
        }
    }

    private var skeletonStrip: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                VStack(spacing: showItemLabels ? 5 : 0) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .tertiarySystemFill))
                        .frame(
                            width: index.isMultiple(of: 3) ? 46 : 34,
                            height: itemDisplaySize.previewHeight
                        )
                    if showItemLabels {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(nsColor: .tertiarySystemFill))
                            .frame(
                                width: itemDisplaySize.minimumTileWidth * 0.64,
                                height: max(6, itemDisplaySize.labelFontSize - 1)
                            )
                    }
                }
                .frame(minWidth: itemDisplaySize.minimumTileWidth)
                .padding(.vertical, showItemLabels ? 7 : 8)
                .padding(.horizontal, 3)
                .background(
                    Color(nsColor: .secondarySystemFill),
                    in: RoundedRectangle(cornerRadius: 11)
                )
            }
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
        .opacity(skeletonIsBright ? 0.82 : 0.42)
        .onAppear {
            guard !skeletonIsBright else { return }
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                skeletonIsBright = true
            }
        }
        .accessibilityLabel("Loading menu bar items")
    }

    private var permissionView: some View {
        HStack(spacing: 12) {
            Image(systemName: "accessibility")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility permission is required")
                    .font(.caption.weight(.semibold))
                Text("It lets the helper discover and press status items directly.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                notchViewModel.close()
                SettingsWindowController.shared.showWindow(tab: "Menu Bar")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
    }

    private var itemStrip: some View {
        HStack(spacing: 4) {
            scrollButton(direction: -1)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(visibleItems) { item in
                        MenuBarItemTile(
                            item: item,
                            previewImage: model.previewImages[item.id],
                            fallbackImage: item.bundleIdentifier.flatMap {
                                model.appIcons[$0]
                            },
                            previewLoadComplete: model.hasCompletedInitialPreviewLoad,
                            displaySize: itemDisplaySize,
                            showsLabel: showItemLabels,
                            isBusy: model.isActivating
                        ) {
                            let anchorWindow = NSApp.currentEvent?.window
                            Task {
                                await model.openMenu(
                                    item,
                                    viewModel: notchViewModel,
                                    anchorWindow: anchorWindow
                                )
                            }
                        }
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 4)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollTargetID, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else {
                            return
                        }
                        if !isDraggingStrip {
                            isDraggingStrip = true
                            coordinator.beginMenuBarInteraction()
                        }
                    }
                    .onEnded { value in
                        let wasDraggingStrip = isDraggingStrip
                        isDraggingStrip = false
                        if wasDraggingStrip {
                            coordinator.holdMenuBarInteraction()
                        }
                        guard abs(value.translation.width) > abs(value.translation.height),
                              abs(value.translation.width) > 12 else {
                            return
                        }

                        let tileStride = itemDisplaySize.minimumTileWidth + 8
                        let distance = abs(value.predictedEndTranslation.width)
                        let itemCount = max(1, Int((distance / tileStride).rounded()))
                        scroll(by: value.translation.width < 0 ? itemCount : -itemCount)
                    }
            )

            scrollButton(direction: 1)
        }
        .onChange(of: scrollTargetID) { _, newValue in
            guard let newValue,
                  let index = visibleItems.firstIndex(where: { $0.id == newValue }) else {
                return
            }
            scrollIndex = index
        }
        .onChange(of: visibleItems.map(\.id)) { _, identifiers in
            guard !identifiers.isEmpty else {
                scrollIndex = 0
                scrollTargetID = nil
                return
            }
            scrollIndex = min(scrollIndex, identifiers.count - 1)
        }
    }

    private func scrollButton(direction: Int) -> some View {
        let isUnavailable = visibleItems.count < 2
            || (direction < 0 && scrollIndex == 0)
            || (direction > 0 && scrollIndex == visibleItems.count - 1)

        return Button {
            coordinator.holdMenuBarInteraction()
            scroll(by: direction * 4)
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.caption.weight(.bold))
                .frame(width: 18, height: 58)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
        .opacity(isUnavailable ? 0.2 : 0.8)
    }

    private func scroll(by offset: Int) {
        guard !visibleItems.isEmpty else { return }
        let targetIndex = min(max(scrollIndex + offset, 0), visibleItems.count - 1)
        guard targetIndex != scrollIndex else { return }

        scrollIndex = targetIndex
        withAnimation(.smooth(duration: 0.2)) {
            scrollTargetID = visibleItems[targetIndex].id
        }
    }

    private func reconcileLayout() {
        let updatedOrder = MenuBarItemLayoutReconciler.order(
            storedIDs: itemOrder,
            currentItems: model.items
        )
        let updatedHiddenIDs = MenuBarItemLayoutReconciler.hiddenIDs(
            storedIDs: hiddenItemIDs,
            currentItems: model.items
        )
        if updatedOrder != itemOrder {
            itemOrder = updatedOrder
        }
        if updatedHiddenIDs != hiddenItemIDs {
            hiddenItemIDs = updatedHiddenIDs
        }
    }

    private func statusView(icon: String, message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(message)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private final class MenuBarSettingsViewModel: ObservableObject {
    @Published private(set) var items: [MenuBarItemDescriptor] = []
    @Published private(set) var appIcons: [String: NSImage] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var accessibilityAuthorized = false
    @Published private(set) var errorMessage: String?
    private var iconLoadTask: Task<Void, Never>?

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let response = await XPCHelperClient.shared.menuBarItems()
        items = response.items
        accessibilityAuthorized = response.accessibilityAuthorized
        errorMessage = response.errorMessage
        loadAppIcons(for: response.items)
    }

    func requestAccessibility() {
        XPCHelperClient.shared.requestAccessibilityAuthorization()
    }

    private func loadAppIcons(for items: [MenuBarItemDescriptor]) {
        let bundleIdentifiers = items.compactMap(\.bundleIdentifier)
        let currentIdentifiers = Set(bundleIdentifiers)
        appIcons = appIcons.filter { currentIdentifiers.contains($0.key) }

        iconLoadTask?.cancel()
        iconLoadTask = Task { [weak self] in
            let icons = await AppIconCache.shared.icons(for: bundleIdentifiers)
            guard !Task.isCancelled else { return }
            self?.appIcons = icons
        }
    }
}

struct MenuBarSettings: View {
    @StateObject private var model = MenuBarSettingsViewModel()
    @ObservedObject private var systemVisibilityController =
        MenuBarSystemVisibilityController.shared
    @State private var screenCaptureAuthorized = CGPreflightScreenCaptureAccess()
    @State private var reorderDropTargetID: String?
    @Default(.menuBarLivePreviews) private var livePreviews
    @Default(.menuBarPreviewRefreshInterval) private var previewRefreshInterval
    @Default(.menuBarItemDisplaySize) private var itemDisplaySize
    @Default(.menuBarItemShowLabels) private var showLabels
    @Default(.menuBarHiddenItemIDs) private var hiddenItemIDs
    @Default(.menuBarItemOrder) private var itemOrder

    private var orderedItems: [MenuBarItemDescriptor] {
        var orderByID: [String: Int] = [:]
        for (index, identifier) in itemOrder.enumerated() where orderByID[identifier] == nil {
            orderByID[identifier] = index
        }
        return model.items.sorted { lhs, rhs in
            let lhsOrder = orderByID[lhs.id] ?? Int.max
            let rhsOrder = orderByID[rhs.id] ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .menuBarAccessEnabled) {
                    Text("Show menu bar access button in the notch")
                }
                Defaults.Toggle(key: .menuBarLivePreviews) {
                    Text("Update status previews live")
                }
                Picker("Live refresh rate", selection: $previewRefreshInterval) {
                    Text("Twice per second").tag(0.5)
                    Text("Once per second").tag(1.0)
                    Text("Every two seconds").tag(2.0)
                }
                .disabled(!livePreviews)

                accessibilityPermissionRow
                screenRecordingPermissionRow
            } header: {
                Text("Menu bar access")
            } footer: {
                Text("Accessibility is required to discover and control menu bar items. Screen Recording is optional and is used only for live previews.")
            }

            Section {
                if systemVisibilityController.isArranging
                    || !systemVisibilityController.hasCompletedSetup {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "Arrange the hidden section once",
                            systemImage: "command"
                        )
                        .font(.headline)

                        Text("Hold Command and drag the thin divider in the macOS menu bar to the right of the items you want to hide. Then Command-drag those items to the divider’s left side.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            if !systemVisibilityController.isArranging {
                                Button("Start arranging") {
                                    systemVisibilityController.beginArrangement()
                                }
                            } else {
                                Button("Done and hide") {
                                    systemVisibilityController.finishArrangement(collapse: true)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Done, keep visible") {
                                    systemVisibilityController.finishArrangement(collapse: false)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Toggle(
                        "Hide items left of the divider",
                        isOn: Binding(
                            get: { systemVisibilityController.isCollapsed },
                            set: { systemVisibilityController.setCollapsed($0) }
                        )
                    )

                    Button("Arrange items again…") {
                        systemVisibilityController.beginArrangement()
                    }
                }
            } header: {
                Text("System menu bar hiding")
            } footer: {
                Text("")
            }

            Section {
                Picker("Item size", selection: $itemDisplaySize) {
                    Text("Compact").tag(MenuBarItemDisplaySize.compact)
                    Text("Standard").tag(MenuBarItemDisplaySize.standard)
                    Text("Large").tag(MenuBarItemDisplaySize.large)
                }
                Defaults.Toggle(key: .menuBarItemShowLabels) {
                    Text("Show item names")
                }
            } header: {
                Text("Notch appearance")
            }

            Section {
                if model.isLoading && model.items.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                } else if !model.accessibilityAuthorized {
                    Text("Grant Accessibility above to list status items.")
                        .foregroundStyle(.secondary)
                } else if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                } else if orderedItems.isEmpty {
                    Text("No menu bar items found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedItems) { item in
                        menuBarItemRow(item)
                    }
                }
            } header: {
                HStack {
                    Text("Item visibility and notch order")
                    Spacer()
                    Text("Notch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 52)
                    Text("Order")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 36)
                    Button {
                        Task { await model.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isLoading)
                }
            } footer: {
                Text("Drag the handle to set the order in the expanded notch. Use the system menu bar hiding section above to arrange the original macOS status items.")
            }

            Section {
                Button("Reset notch item layout") {
                    itemOrder = model.items.map(\.id)
                    hiddenItemIDs = []
                    itemDisplaySize = .standard
                    showLabels = true
                }
            }
        }
        .navigationTitle("Menu Bar")
        .task {
            await model.load()
            reconcileOrder()
            screenCaptureAuthorized = CGPreflightScreenCaptureAccess()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        }
        .onDisappear {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)
        ) { notification in
            Task {
                await model.load()
                reconcileOrder()
                if notification.userInfo?["granted"] as? Bool == true {
                    await MenuBarItemsViewModel.shared.load(
                        capturePreviews: livePreviews
                    )
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await refreshPermissionState() }
        }
        .onChange(of: model.items.map(\.id)) {
            reconcileOrder()
        }
    }

    private var accessibilityPermissionRow: some View {
        LabeledContent("Accessibility") {
            HStack(spacing: 8) {
                Label {
                    Text(
                        model.accessibilityAuthorized
                            ? String(localized: "Allowed")
                            : String(localized: "Required")
                    )
                } icon: {
                    Image(
                        systemName: model.accessibilityAuthorized
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle"
                    )
                }
                .foregroundStyle(model.accessibilityAuthorized ? .green : .secondary)

                if !model.accessibilityAuthorized {
                    Button("Allow") {
                        model.requestAccessibility()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    privacySettingsButton(pane: "Privacy_Accessibility")
                }
            }
        }
    }

    private var screenRecordingPermissionRow: some View {
        LabeledContent("Screen Recording") {
            HStack(spacing: 8) {
                Label {
                    Text(
                        screenCaptureAuthorized
                            ? String(localized: "Allowed")
                            : String(localized: "Required for live previews")
                    )
                } icon: {
                    Image(
                        systemName: screenCaptureAuthorized
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle"
                    )
                }
                .foregroundStyle(screenCaptureAuthorized ? .green : .secondary)

                if !screenCaptureAuthorized {
                    Button("Allow") {
                        requestScreenRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    privacySettingsButton(pane: "Privacy_ScreenCapture")
                }
            }
        }
    }

    private func privacySettingsButton(pane: String) -> some View {
        Button {
            openPrivacySettings(pane: pane)
        } label: {
            Image(systemName: "gear")
        }
        .buttonStyle(.borderless)
        .help("Open System Settings")
    }

    private func requestScreenRecording() {
        Task {
            _ = await Task.detached(priority: .userInitiated) {
                CGRequestScreenCaptureAccess()
            }.value
            await refreshPermissionState()
        }
    }

    private func openPrivacySettings(pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshPermissionState() async {
        let wasScreenCaptureAuthorized = screenCaptureAuthorized
        screenCaptureAuthorized = CGPreflightScreenCaptureAccess()
        await model.load()
        reconcileOrder()

        if !wasScreenCaptureAuthorized,
           screenCaptureAuthorized,
           livePreviews {
            await MenuBarItemsViewModel.shared.load(capturePreviews: true)
        }
    }

    private func menuBarItemRow(_ item: MenuBarItemDescriptor) -> some View {
        HStack(spacing: 10) {
            Group {
                if let bundleIdentifier = item.bundleIdentifier,
                   let image = model.appIcons[bundleIdentifier] {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "menubar.rectangle")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .lineLimit(1)
                if item.applicationName != item.displayName {
                    Text(item.applicationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Toggle("", isOn: notchVisibilityBinding(for: item.id))
                .labelsHidden()
                .frame(width: 52)
                .help("Show this item in the notch")

            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
                .draggable(item.id) {
                    Label(item.displayName, systemImage: "line.3.horizontal")
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .help("Drag to reorder this item in the notch")
        }
        .padding(.vertical, 2)
        .background(
            reorderDropTargetID == item.id
                ? Color.accentColor.opacity(0.12)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .dropDestination(for: String.self) { identifiers, _ in
            guard let sourceID = identifiers.first else { return false }
            moveItem(sourceID: sourceID, beforeOrAfter: item.id)
            reorderDropTargetID = nil
            return true
        } isTargeted: { isTargeted in
            if isTargeted {
                reorderDropTargetID = item.id
            } else if reorderDropTargetID == item.id {
                reorderDropTargetID = nil
            }
        }
        .animation(.smooth(duration: 0.18), value: reorderDropTargetID)
    }

    private func notchVisibilityBinding(for identifier: String) -> Binding<Bool> {
        Binding(
            get: { !hiddenItemIDs.contains(identifier) },
            set: { isVisible in
                var hiddenIDs = Set(hiddenItemIDs)
                if isVisible {
                    hiddenIDs.remove(identifier)
                } else {
                    hiddenIDs.insert(identifier)
                }
                hiddenItemIDs = Array(hiddenIDs)
            }
        )
    }

    private func reconcileOrder() {
        let updatedOrder = MenuBarItemLayoutReconciler.order(
            storedIDs: itemOrder,
            currentItems: model.items
        )
        let updatedHiddenIDs = MenuBarItemLayoutReconciler.hiddenIDs(
            storedIDs: hiddenItemIDs,
            currentItems: model.items
        )
        if updatedOrder != itemOrder {
            itemOrder = updatedOrder
        }
        if updatedHiddenIDs != hiddenItemIDs {
            hiddenItemIDs = updatedHiddenIDs
        }
    }

    private func moveItem(sourceID: String, beforeOrAfter destinationID: String) {
        guard sourceID != destinationID,
              let sourceIndex = itemOrder.firstIndex(of: sourceID),
              let destinationIndex = itemOrder.firstIndex(of: destinationID) else {
            return
        }

        var updatedOrder = itemOrder
        updatedOrder.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        )
        withAnimation(.smooth(duration: 0.2)) {
            itemOrder = updatedOrder
        }
    }
}

/// ScreenCaptureKit cannot render status windows that macOS has moved outside
/// all display bounds. CoreGraphics still exposes its public Window List array
/// capture symbol at runtime, including on SDKs where the declaration itself is
/// unavailable. Keep this compatibility path isolated and optional so a future
/// removal of the symbol falls back cleanly to ScreenCaptureKit.
private enum LegacyMenuBarWindowCapture {
    struct Request: Sendable {
        let itemID: String
        let frame: CGRect
        let windowID: CGWindowID
    }

    struct Result: @unchecked Sendable {
        let images: [String: CGImage]
    }

    private typealias CaptureFunction = @convention(c) (
        CGRect,
        CFArray,
        UInt32
    ) -> Unmanaged<CGImage>?

    private static let captureFunction: CaptureFunction? = {
        guard let symbol = dlsym(
            UnsafeMutableRawPointer(bitPattern: -2),
            "CGWindowListCreateImageFromArray"
        ) else {
            return nil
        }
        return unsafeBitCast(symbol, to: CaptureFunction.self)
    }()

    static func capture(_ requests: [Request]) -> Result {
        guard !requests.isEmpty, captureFunction != nil else {
            return Result(images: [:])
        }

        var images: [String: CGImage] = [:]
        let unionFrame = requests.map(\.frame).reduce(CGRect.null) { $0.union($1) }

        if let compositeImage = captureImage(
            windowIDs: requests.map(\.windowID)
        ), compositeMatchesFrame(compositeImage, frame: unionFrame) {
            let scaleX = CGFloat(compositeImage.width) / unionFrame.width
            let scaleY = CGFloat(compositeImage.height) / unionFrame.height
            let imageBounds = CGRect(
                x: 0,
                y: 0,
                width: compositeImage.width,
                height: compositeImage.height
            )

            for request in requests {
                let cropRect = CGRect(
                    x: (request.frame.minX - unionFrame.minX) * scaleX,
                    y: (request.frame.minY - unionFrame.minY) * scaleY,
                    width: request.frame.width * scaleX,
                    height: request.frame.height * scaleY
                ).integral.intersection(imageBounds)
                guard cropRect.width > 0,
                      cropRect.height > 0,
                      let croppedImage = compositeImage.cropping(to: cropRect) else {
                    continue
                }
                images[request.itemID] = croppedImage
            }
        }

        // Match Ice's resilience: if the composite dimensions were unexpected,
        // retry only the missing windows through the same array API.
        for request in requests where images[request.itemID] == nil {
            if let image = captureImage(windowIDs: [request.windowID]) {
                images[request.itemID] = image
            }
        }

        return Result(images: images)
    }

    private static func captureImage(windowIDs: [CGWindowID]) -> CGImage? {
        guard let captureFunction, !windowIDs.isEmpty else { return nil }

        let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(
            capacity: windowIDs.count
        )
        defer { pointer.deallocate() }
        for (index, windowID) in windowIDs.enumerated() {
            pointer[index] = UnsafeRawPointer(bitPattern: UInt(windowID))
        }
        guard let windowArray = CFArrayCreate(
            kCFAllocatorDefault,
            pointer,
            windowIDs.count,
            nil
        ) else {
            return nil
        }

        let options: CGWindowImageOption = [
            .boundsIgnoreFraming,
            .bestResolution,
        ]
        return captureFunction(
            .null,
            windowArray,
            options.rawValue
        )?.takeRetainedValue()
    }

    private static func compositeMatchesFrame(
        _ image: CGImage,
        frame: CGRect
    ) -> Bool {
        guard frame.width > 0, frame.height > 0, image.height > 0 else {
            return false
        }
        let scale = CGFloat(image.height) / frame.height
        return abs(CGFloat(image.width) - frame.width * scale) <= 2
    }
}

@MainActor
private final class MenuBarItemPreviewProvider {
    static let shared = MenuBarItemPreviewProvider()

    private struct MatchedWindow {
        let item: MenuBarItemDescriptor
        let frame: CGRect
        let window: SCWindow
        let display: SCDisplay?
    }

    private struct WindowCandidate {
        let item: MenuBarItemDescriptor
        let frame: CGRect
        let window: SCWindow
        let distance: CGFloat
    }

    func capturePreviews(
        for items: [MenuBarItemDescriptor]
    ) async -> [String: NSImage] {
        guard CGPreflightScreenCaptureAccess() else { return [:] }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        } catch {
            return [:]
        }

        let matches = matchedWindows(
            for: items,
            windows: content.windows,
            displays: content.displays
        )

        var previews: [String: NSImage] = [:]
        for display in content.displays {
            guard !Task.isCancelled else { break }
            let displayMatches = matches.filter {
                $0.display?.displayID == display.displayID
            }
            guard !displayMatches.isEmpty else { continue }
            previews.merge(await capture(
                displayMatches,
                on: display
            )) { _, refreshed in
                refreshed
            }
        }

        let unresolvedMatches = matches.filter { previews[$0.item.id] == nil }
        if !unresolvedMatches.isEmpty {
            let requests = unresolvedMatches.map {
                LegacyMenuBarWindowCapture.Request(
                    itemID: $0.item.id,
                    frame: $0.window.frame,
                    windowID: $0.window.windowID
                )
            }
            let legacyResult = await Task.detached(priority: .userInitiated) {
                LegacyMenuBarWindowCapture.capture(requests)
            }.value
            let logicalSizes = Dictionary(
                uniqueKeysWithValues: requests.map { ($0.itemID, $0.frame.size) }
            )
            for (itemID, image) in legacyResult.images {
                let logicalSize = logicalSizes[itemID]
                    ?? CGSize(width: image.width, height: image.height)
                previews[itemID] = NSImage(
                    cgImage: image,
                    size: logicalSize
                )
            }
        }

        // Keep ScreenCaptureKit as a final fallback if the legacy public
        // Window List symbol is removed by a future macOS release.
        for match in matches where previews[match.item.id] == nil {
            guard !Task.isCancelled else { break }
            if let preview = await capture(match) {
                previews[match.item.id] = preview
            }
        }

        return previews
    }

    private func matchedWindows(
        for items: [MenuBarItemDescriptor],
        windows: [SCWindow],
        displays: [SCDisplay]
    ) -> [MatchedWindow] {
        let statusItemWindowLevel = Int(CGWindowLevelForKey(.statusWindow))
        let statusWindows = windows.filter { window in
            let frame = window.frame
            let ownerBundleIdentifier = window.owningApplication?.bundleIdentifier ?? ""
            return window.windowLayer == statusItemWindowLevel
                && window.title != "BoringNotchHiddenItemsBoundary"
                && !ownerBundleIdentifier.hasPrefix("theboringteam.boringnotch")
                && frame.width >= 4
                && frame.height >= 4
                && frame.height <= 100
        }

        var candidates: [WindowCandidate] = []
        for item in items {
            let frame = CGRect(
                x: item.frameX,
                y: item.frameY,
                width: item.frameWidth,
                height: item.frameHeight
            )
            guard frame.width > 0, frame.height > 0 else { continue }

            let searchFrame = frame.insetBy(dx: -24, dy: -20)
            for window in statusWindows {
                let windowFrame = window.frame
                let itemIdentity = (item.accessibilityIdentifier ?? item.title)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let windowIdentity = window.title?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let hasIdentityMatch = itemIdentity?.isEmpty == false
                    && itemIdentity == windowIdentity
                guard windowFrame.width <= max(420, frame.width + 100),
                      hasIdentityMatch || windowFrame.intersects(searchFrame) else {
                    continue
                }
                candidates.append(
                    WindowCandidate(
                        item: item,
                        frame: windowFrame,
                        window: window,
                        // Exact AX identifier ↔ window-title matches survive
                        // moves into an off-screen hidden section. Prefer them
                        // over all geometric candidates.
                        distance: windowFrame.menuBarPreviewDistance(to: frame)
                            + (hasIdentityMatch ? -100_000 : 0)
                    )
                )
            }
        }

        var claimedItems = Set<String>()
        var claimedWindows = Set<CGWindowID>()
        var matches: [MatchedWindow] = []
        for candidate in candidates.sorted(by: { $0.distance < $1.distance }) {
            guard !claimedItems.contains(candidate.item.id),
                  !claimedWindows.contains(candidate.window.windowID) else {
                continue
            }
            claimedItems.insert(candidate.item.id)
            claimedWindows.insert(candidate.window.windowID)
            matches.append(
                MatchedWindow(
                    item: candidate.item,
                    frame: candidate.frame,
                    window: candidate.window,
                    display: display(containing: candidate.window.frame, in: displays)
                )
            )
        }
        return matches
    }

    private func display(containing frame: CGRect, in displays: [SCDisplay]) -> SCDisplay? {
        guard let display = displays.max(by: { lhs, rhs in
            lhs.frame.intersection(frame).area < rhs.frame.intersection(frame).area
        }), display.frame.intersection(frame).area > 0 else {
            return nil
        }
        return display
    }

    private func capture(
        _ matches: [MatchedWindow],
        on display: SCDisplay
    ) async -> [String: NSImage] {
        let unionFrame = matches.map(\.window.frame).reduce(CGRect.null) { $0.union($1) }
        let captureFrame = unionFrame
            .insetBy(dx: -2, dy: -2)
            .intersection(display.frame)
        guard !captureFrame.isNull, captureFrame.width > 0, captureFrame.height > 0 else {
            return [:]
        }

        let scale: CGFloat = 2
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = captureFrame.offsetBy(
            dx: -display.frame.minX,
            dy: -display.frame.minY
        )
        configuration.width = max(1, Int((captureFrame.width * scale).rounded()))
        configuration.height = max(1, Int((captureFrame.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsDisplay = true
        configuration.ignoreGlobalClipDisplay = true
        configuration.backgroundColor = CGColor.clear
        configuration.shouldBeOpaque = false

        let image: CGImage
        do {
            var seenWindowIDs = Set<CGWindowID>()
            let windows = matches.compactMap { match -> SCWindow? in
                guard seenWindowIDs.insert(match.window.windowID).inserted else {
                    return nil
                }
                return match.window
            }
            image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(
                    display: display,
                    including: windows
                ),
                configuration: configuration
            )
        } catch {
            return [:]
        }

        let pixelScaleX = CGFloat(image.width) / captureFrame.width
        let pixelScaleY = CGFloat(image.height) / captureFrame.height
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var previews: [String: NSImage] = [:]

        for match in matches {
            let frame = match.frame
            let cropRect = CGRect(
                x: (frame.minX - captureFrame.minX) * pixelScaleX,
                y: (frame.minY - captureFrame.minY) * pixelScaleY,
                width: frame.width * pixelScaleX,
                height: frame.height * pixelScaleY
            ).integral.intersection(imageBounds)
            guard cropRect.width > 0,
                  cropRect.height > 0,
                  let croppedImage = image.cropping(to: cropRect) else {
                continue
            }

            previews[match.item.id] = NSImage(
                cgImage: croppedImage,
                size: NSSize(width: frame.width, height: frame.height)
            )
        }

        return previews
    }

    private func capture(_ match: MatchedWindow) async -> NSImage? {
        let windowFrame = match.window.frame
        guard windowFrame.width > 0, windowFrame.height > 0 else { return nil }

        let scale: CGFloat = 2
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((windowFrame.width * scale).rounded()))
        configuration.height = max(1, Int((windowFrame.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.backgroundColor = CGColor.clear
        configuration.shouldBeOpaque = false

        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: match.window),
                configuration: configuration
            )
        } catch {
            return nil
        }

        let pixelScaleX = CGFloat(image.width) / windowFrame.width
        let pixelScaleY = CGFloat(image.height) / windowFrame.height
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = CGRect(
            x: (match.frame.minX - windowFrame.minX) * pixelScaleX,
            y: (match.frame.minY - windowFrame.minY) * pixelScaleY,
            width: match.frame.width * pixelScaleX,
            height: match.frame.height * pixelScaleY
        ).integral.intersection(imageBounds)
        guard cropRect.width > 0,
              cropRect.height > 0,
              let croppedImage = image.cropping(to: cropRect) else {
            return nil
        }

        return NSImage(
            cgImage: croppedImage,
            size: NSSize(width: match.frame.width, height: match.frame.height)
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
    }

    func menuBarPreviewDistance(to other: CGRect) -> CGFloat {
        abs(midX - other.midX)
            + abs(midY - other.midY)
            + abs(width - other.width) * 2
            + abs(height - other.height)
    }

}

@MainActor
private final class MenuBarMenuPresenter: NSObject {
    static let shared = MenuBarMenuPresenter()

    func present(
        entries: [MenuBarMenuEntry],
        for item: MenuBarItemDescriptor,
        viewModel: BoringViewModel,
        anchorWindow: NSWindow?
    ) {
        guard let window = anchorWindow
                ?? NSApp.keyWindow
                ?? NSApp.windows.first(where: { $0.isVisible }),
              let contentView = window.contentView else {
            return
        }

        let menu = makeMenu(entries: entries, item: item, viewModel: viewModel)
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let viewPoint = contentView.convert(windowPoint, from: nil)
        menu.popUp(positioning: nil, at: viewPoint, in: contentView)
    }

    private func makeMenu(
        entries: [MenuBarMenuEntry],
        item: MenuBarItemDescriptor,
        viewModel: BoringViewModel
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let systemUsesDarkAppearance = UserDefaults.standard.string(
            forKey: "AppleInterfaceStyle"
        ) == "Dark"
        menu.appearance = NSAppearance(
            named: systemUsesDarkAppearance ? .darkAqua : .aqua
        )

        for entry in entries {
            if entry.isSeparator {
                menu.addItem(.separator())
                continue
            }

            let menuItem = NSMenuItem(
                title: entry.title,
                action: entry.children.isEmpty ? #selector(selectMenuItem(_:)) : nil,
                keyEquivalent: entry.keyEquivalent ?? ""
            )
            menuItem.target = entry.children.isEmpty ? self : nil
            menuItem.isEnabled = entry.isEnabled
            menuItem.state = entry.isMarked ? .on : .off
            menuItem.keyEquivalentModifierMask = modifierFlags(
                from: entry.keyEquivalentModifiers
            )
            menuItem.representedObject = MenuBarMenuActionPayload(
                item: item,
                entry: entry,
                viewModel: viewModel
            )

            if !entry.children.isEmpty {
                menuItem.submenu = makeMenu(
                    entries: entry.children,
                    item: item,
                    viewModel: viewModel
                )
            }
            menu.addItem(menuItem)
        }

        return menu
    }

    private func modifierFlags(from accessibilityModifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if accessibilityModifiers & (1 << 3) == 0 { flags.insert(.command) }
        if accessibilityModifiers & (1 << 0) != 0 { flags.insert(.shift) }
        if accessibilityModifiers & (1 << 1) != 0 { flags.insert(.option) }
        if accessibilityModifiers & (1 << 2) != 0 { flags.insert(.control) }
        return flags
    }

    @objc private func selectMenuItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? MenuBarMenuActionPayload else { return }
        payload.viewModel?.close()

        Task {
            let response = await XPCHelperClient.shared.activateMenuEntry(
                payload.entry,
                for: payload.item
            )
            guard !response.success else { return }

            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn’t select menu item")
            alert.informativeText = response.errorMessage
                ?? String(localized: "Open the menu again and try once more.")
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

@MainActor
private final class MenuBarMenuActionPayload: NSObject {
    let item: MenuBarItemDescriptor
    let entry: MenuBarMenuEntry
    weak var viewModel: BoringViewModel?

    init(
        item: MenuBarItemDescriptor,
        entry: MenuBarMenuEntry,
        viewModel: BoringViewModel
    ) {
        self.item = item
        self.entry = entry
        self.viewModel = viewModel
    }
}

private struct MenuBarItemTile: View {
    let item: MenuBarItemDescriptor
    let previewImage: NSImage?
    let fallbackImage: NSImage?
    let previewLoadComplete: Bool
    let displaySize: MenuBarItemDisplaySize
    let showsLabel: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: showsLabel ? 5 : 0) {
                icon
                    .frame(width: previewWidth, height: displaySize.previewHeight)
                if showsLabel {
                    Text(item.displayName)
                        .font(.system(size: displaySize.labelFontSize, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: tileWidth - 6)
                }
            }
            .frame(minWidth: displaySize.minimumTileWidth)
            .padding(.vertical, showsLabel ? 7 : 8)
            .padding(.horizontal, 3)
            .background(Color(nsColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 11))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help(helpText)
    }

    @ViewBuilder
    private var icon: some View {
        if !previewLoadComplete {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .tertiarySystemFill))
                .overlay {
                    ProgressView()
                        .controlSize(.mini)
                }
        } else if let previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else if let fallbackImage {
            Image(nsImage: fallbackImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 19))
                .foregroundStyle(.secondary)
        }
    }

    private var previewWidth: CGFloat {
        guard previewImage != nil || !previewLoadComplete else { return 34 }
        let aspectWidth = CGFloat(item.frameWidth)
            / max(CGFloat(item.frameHeight), 1)
            * displaySize.previewHeight
        return min(max(aspectWidth, 30), displaySize.maximumPreviewWidth)
    }

    private var tileWidth: CGFloat {
        max(displaySize.minimumTileWidth, previewWidth + 12)
    }

    private var helpText: String {
        return item.title.map { "\(item.displayName) — \($0)" } ?? item.displayName
    }
}

#Preview {
    MenuBarItemsView(isActive: true)
        .environmentObject(BoringViewModel())
        .frame(width: 600, height: 120)
        .background(.black)
}
