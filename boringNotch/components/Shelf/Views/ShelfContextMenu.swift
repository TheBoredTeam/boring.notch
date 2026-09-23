//
//  ShelfContextMenu.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  AppKit context-menu construction and action dispatch for shelf items.
//  Extracted from ShelfItemViewModel: the VM keeps item state and routes
//  clicks here.
//

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreServices
import ObjectiveC

// MARK: - Localization helpers
struct Strings {
    static let open = String(localized: "Open", comment: "Context menu item: Open")
    static let openWith = String(localized: "Open With", comment: "Context menu item: Open With")
    static let noCompatibleApps = String(localized: "No Compatible Apps Found", comment: "Context menu item: No Compatible Apps Found")
    static let other = String(localized: "Other…", comment: "Context menu item: Other…")
    static let showInFinder = String(localized: "Show in Finder", comment: "Context menu item: Show in Finder")
    static let quickLook = String(localized: "Quick Look", comment: "Context menu item: Quick Look")
    static let share = String(localized: "Share…", comment: "Context menu item: Share…")
    static let imageActions = String(localized: "Image Actions", comment: "Context menu item: Image Actions")
    static let removeBackground = String(localized: "Remove Background", comment: "Context menu item: Remove Background")
    static let convertImage = String(localized: "Convert Image…", comment: "Context menu item: Convert Image…")
    static let createPDF = String(localized: "Create PDF", comment: "Context menu item: Create PDF")
    static let compress = String(localized: "Compress", comment: "Context menu item: Compress")
    static let rename = String(localized: "Rename", comment: "Context menu item: Rename")
    static let copy = String(localized: "Copy", comment: "Context menu item: Copy")
    static let copyPath = String(localized: "Copy Path", comment: "Context menu item: Copy Path")
    static let remove = String(localized: "Remove", comment: "Context menu item: Remove")
}

enum ContextMenuAction: String {
    case quickLook
    case open
    case share
    case rename
    case showInFinder
    case copyPath
    case copy
    case remove
    case removeBackground
    case convertImage
    case createPDF
    case compress
}

@MainActor
enum ShelfContextMenuBuilder {
static func present(
    item: ShelfItem, event: NSEvent, in view: NSView,
    onShare: @escaping (NSView?) -> Void, onQuickLook: @escaping ([URL]) -> Void
) {
    let selection = ShelfSelectionModel.shared
    if !selection.isSelected(item.id) { selection.selectSingle(item) }
    let menu = makeMenu(item: item, in: view,
                        selectedItems: selection.selectedItems(in: ShelfStateViewModel.shared.items),
                        onShare: onShare, onQuickLook: onQuickLook)
    NSMenu.popUpContextMenu(menu, with: event, for: view)
}

struct OpenWithApplication: Sendable {
    let url: URL
    let title: String
    let isDefault: Bool
    let iconData: Data?
}

static func openWithTarget(
    for clickedItem: ShelfItem, selectedItems: [ShelfItem], shelfState: ShelfStateViewModel
) async -> (item: ShelfItem, url: URL)? {
    let candidates = [clickedItem] + selectedItems.filter { $0.id != clickedItem.id }
    for candidate in candidates {
        guard !Task.isCancelled else { return nil }
        guard let current = shelfState.items.first(where: { $0.id == candidate.id }) else { continue }
        switch current.kind {
        case .file:
            guard let file = await shelfState.resolveFile(
                for: current, intent: .userInitiated, refresh: true
            ), !file.isDirectory,
               let resolvedItem = shelfState.items.first(where: { $0.id == current.id }) else { continue }
            return (resolvedItem, file.url)
        case .link(let url): return (current, url)
        case .text: continue
        }
    }
    return nil
}

static func openWithApplications(for url: URL) async -> [OpenWithApplication] {
    return await ShelfBookmarkResolutionExecutor.shared.execute {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let workspace = NSWorkspace.shared
        var applications = workspace.urlsForApplications(toOpen: url)
        if applications.isEmpty, url.isFileURL,
           let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            applications = workspace.urlsForApplications(toOpen: type)
        }
        let defaultURL = workspace.urlForApplication(toOpen: url)
        if let defaultURL { applications.insert(defaultURL, at: 0) }
        var seen: Set<URL> = []
        return applications.filter { seen.insert($0).inserted }.map { app in
            let title = (try? app.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                ?? app.deletingPathExtension().lastPathComponent
            let icon = workspace.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            return OpenWithApplication(url: app, title: title,
                                       isDefault: app == defaultURL, iconData: icon.tiffRepresentation)
        }
    }
}

static func makeMenu(
    item: ShelfItem, in view: NSView, selectedItems: [ShelfItem],
    onShare: @escaping (NSView?) -> Void, onQuickLook: @escaping ([URL]) -> Void,
    shelfState: ShelfStateViewModel = .shared,
    discoverApplications: ((URL) async -> [OpenWithApplication])? = nil
) -> NSMenu {
    let menu = NSMenu()
    var openWithSubmenu: NSMenu?

    func addMenuItem(title: String, contextAction: ContextMenuAction? = nil) {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let contextAction {
            mi.representedObject = contextAction.rawValue
        }
        menu.addItem(mi)
    }

    let resolvedFiles = selectedItems.compactMap {
        shelfState.resolvedFile(for: $0)
    }
    let hasSelectedFiles = selectedItems.contains { item in
        if case .file = item.kind { return true }
        return false
    }
    let selectedLinkURLs: [URL] = selectedItems.compactMap { itm in
        if case .link(let url) = itm.kind { return url }
        return nil
    }
    let hasOpenableItems = selectedItems.contains { selectedItem in
        if case .link = selectedItem.kind { return true }
        if case .file = selectedItem.kind {
            return shelfState.resolvedFile(for: selectedItem)?.isDirectory != true
        }
        return false
    }

    if hasOpenableItems {
        addMenuItem(title: Strings.open, contextAction: .open)
    }

    if hasOpenableItems {
        let openWith = NSMenuItem(title: Strings.openWith, action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let loading = NSMenuItem(title: String(localized: "Loading…"), action: nil, keyEquivalent: "")
        loading.isEnabled = false
        submenu.addItem(loading)
        submenu.addItem(.separator())
        openWithSubmenu = submenu
        let other = NSMenuItem(title: Strings.other, action: nil, keyEquivalent: "")
        other.representedObject = "__OTHER__"
        submenu.addItem(other)

        openWith.submenu = submenu
        menu.addItem(openWith)
    }

    if hasSelectedFiles { addMenuItem(title: Strings.showInFinder, contextAction: .showInFinder) }
    // Allow Quick Look for files and link URLs
    if hasSelectedFiles || !selectedLinkURLs.isEmpty {
        // Add Quick Look menu item
        let quickLookItem = NSMenuItem(title: Strings.quickLook, action: nil, keyEquivalent: "")
        quickLookItem.representedObject = ContextMenuAction.quickLook.rawValue
        menu.addItem(quickLookItem)

        // Add Slideshow as alternate menu item (shown when Option key is held)
        let slideshowItem = NSMenuItem(title: Strings.quickLook, action: nil, keyEquivalent: "")
        slideshowItem.representedObject = ContextMenuAction.quickLook.rawValue
        slideshowItem.isAlternate = true
        slideshowItem.keyEquivalentModifierMask = [.option]
        menu.addItem(slideshowItem)
    }

    menu.addItem(NSMenuItem.separator())
    addMenuItem(title: Strings.share, contextAction: .share)

    // Add image processing options for image files grouped under "Image Actions"
    let imageURLs = resolvedFiles.filter {
        $0.contentTypeIdentifier.flatMap(UTType.init)?.conforms(to: .image) == true
    }.map { $0.url }
    if !imageURLs.isEmpty {
        menu.addItem(NSMenuItem.separator())

        let imageActions = NSMenuItem(title: Strings.imageActions, action: nil, keyEquivalent: "")
        let imageSubmenu = NSMenu()

        // Remove Background - only for single images
        if imageURLs.count == 1 {
            let removeBg = NSMenuItem(title: Strings.removeBackground, action: nil, keyEquivalent: "")
            removeBg.representedObject = ContextMenuAction.removeBackground.rawValue
            imageSubmenu.addItem(removeBg)
        }

        // Convert Image - only for single images
        if imageURLs.count == 1 {
            let convertItem = NSMenuItem(title: Strings.convertImage, action: nil, keyEquivalent: "")
            convertItem.representedObject = ContextMenuAction.convertImage.rawValue
            imageSubmenu.addItem(convertItem)
        }

        // Create PDF - for one or more images
        let createPDF = NSMenuItem(title: Strings.createPDF, action: nil, keyEquivalent: "")
        createPDF.representedObject = ContextMenuAction.createPDF.rawValue
        imageSubmenu.addItem(createPDF)

        imageActions.submenu = imageSubmenu
        menu.addItem(imageActions)
        menu.addItem(NSMenuItem.separator())
    }

    // Add compression option for files/folders (single or multiple)
    if hasSelectedFiles {
        let compressItem = NSMenuItem(title: Strings.compress, action: nil, keyEquivalent: "")
        compressItem.representedObject = ContextMenuAction.compress.rawValue
        menu.addItem(compressItem)
    }

    if selectedItems.count == 1, case .file = item.kind { addMenuItem(title: Strings.rename, contextAction: .rename) }

    // Always show "Copy" for all item types
    addMenuItem(title: Strings.copy, contextAction: .copy)
    // If there are file URLs, add "Copy Path" as an alternate menu item (Option key)
    if hasSelectedFiles {
        let copyPathItem = NSMenuItem(title: Strings.copyPath, action: nil, keyEquivalent: "")
        copyPathItem.representedObject = ContextMenuAction.copyPath.rawValue
        copyPathItem.isAlternate = true
        copyPathItem.keyEquivalentModifierMask = [.option]
        menu.addItem(copyPathItem)
    }

    menu.addItem(NSMenuItem.separator())
    addMenuItem(title: Strings.remove, contextAction: .remove)

    let actionTarget = MenuActionTarget(item: item, selectedItems: selectedItems, shelfState: shelfState, view: view, onShare: onShare, onQuickLook: onQuickLook)

    for menuItem in menu.items {
        if menuItem.isSeparatorItem { continue }
        menuItem.target = actionTarget
        menuItem.action = #selector(MenuActionTarget.handle(_:))

        if let submenu = menuItem.submenu {
            for subItem in submenu.items {
                if !subItem.isSeparatorItem && subItem.isEnabled {
                    subItem.target = actionTarget
                    subItem.action = #selector(MenuActionTarget.handle(_:))
                }
            }
        }
    }

    menu.retainActionTarget(actionTarget)
    menu.delegate = actionTarget
    if let submenu = openWithSubmenu {
        actionTarget.discoveryTask = Task { [weak actionTarget, weak submenu] in
            let target = await openWithTarget(for: item, selectedItems: selectedItems, shelfState: shelfState)
            guard !Task.isCancelled else { return }
            let applications: [OpenWithApplication]
            if let target {
                applications = await (discoverApplications ?? openWithApplications)(target.url)
                guard shelfState.containsCurrentVersion(of: target.item) else { return }
            } else {
                applications = []
            }
            guard !Task.isCancelled, let actionTarget, let submenu else { return }
            submenu.removeItem(at: 0)
            if applications.isEmpty {
                let unavailable = NSMenuItem(title: Strings.noCompatibleApps, action: nil, keyEquivalent: "")
                unavailable.isEnabled = false
                submenu.insertItem(unavailable, at: 0)
            }
            for (index, application) in applications.enumerated() {
                let entry = NSMenuItem(title: application.title,
                                       action: #selector(MenuActionTarget.handle(_:)), keyEquivalent: "")
                entry.state = application.isDefault ? .on : .off
                entry.representedObject = application.url
                entry.image = application.iconData.flatMap(NSImage.init(data:))
                entry.target = actionTarget
                submenu.insertItem(entry, at: index)
            }
        }
    }

    return menu
    }
}

@MainActor
private final class MenuActionTarget: NSObject, NSMenuDelegate {
    var discoveryTask: Task<Void, Never>?

    func menuDidClose(_ menu: NSMenu) {
        discoveryTask?.cancel()
        discoveryTask = nil
    }

    private static var copiedURLs: [URL] = []
    let item: ShelfItem
    let selectedItems: [ShelfItem]
    let shelfState: ShelfStateViewModel
    weak var view: NSView?
    let onShare: (NSView?) -> Void
    let onQuickLook: ([URL]) -> Void

    // Keep associated objects (like accessory view handlers) without magic keys
    private static var sliderHandlerAssoc = AssociatedObject<AnyObject>()

    init(item: ShelfItem, selectedItems: [ShelfItem], shelfState: ShelfStateViewModel, view: NSView, onShare: @escaping (NSView?) -> Void, onQuickLook: @escaping ([URL]) -> Void) {
        self.item = item
        self.selectedItems = selectedItems
        self.shelfState = shelfState
        self.view = view
        self.onShare = onShare
        self.onQuickLook = onQuickLook
    }

    @MainActor @objc func handle(_ sender: NSMenuItem) {
        if let marker = sender.representedObject as? String, marker == "__OTHER__" {
            openWithPanel()
            return
        }

        // Dispatch on the action tag, never the (localized) title.
        let actionRaw = sender.representedObject as? String
        let action = actionRaw.flatMap { ContextMenuAction(rawValue: $0) }

        if let appURL = sender.representedObject as? URL {
            let selected = selectedItems

            Task {
                    var allSelectedURLs: [URL] = []

                    allSelectedURLs = await resolveURLs(for: selected)

                    guard !allSelectedURLs.isEmpty else { return }

                    let config = NSWorkspace.OpenConfiguration()

                    let fileURLs = allSelectedURLs.filter { $0.isFileURL }
                    do {
                        if !fileURLs.isEmpty {
                            _ = try await fileURLs.accessSecurityScopedResources { _ in
                                try await NSWorkspace.shared.open(allSelectedURLs, withApplicationAt: appURL, configuration: config)
                            }
                        } else {
                            try await NSWorkspace.shared.open(allSelectedURLs, withApplicationAt: appURL, configuration: config)
                        }
                    } catch {
                        Log.shelf.error("❌ Failed to open with application: \(error.localizedDescription)")
                    }
            }
            return
        }

        switch action {
        case .quickLook?:
            // Handle all selected items for Quick Look, not just the clicked item
            let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
            Task {
                let urls = await resolveURLs(for: selected)
                if !urls.isEmpty {
                    onQuickLook(urls)
                }
            }

        case .open?:
            let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
            for it in selected { ShelfActionService.open(it) }

        case .share?:
            onShare(view)

        case .rename?:
            let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
            if selected.count == 1, let single = selected.first { showRenameDialog(for: single) }

        case .showInFinder?:
            let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
            Task {
                let urls = await selected.asyncCompactMap { item -> URL? in
                    if case .file = item.kind {
                        return await ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item)
                    }
                    return nil
                }
                if !urls.isEmpty {
                    await urls.accessSecurityScopedResources { accessibleURLs in
                        NSWorkspace.shared.activateFileViewerSelecting(accessibleURLs)
                    }
                }
            }

        case .copyPath?:
            let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
            Task {
                let paths = await resolveFileURLs(for: selected).map(\.path)
                if !paths.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
                }
            }

        case .copy?:
            let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
            let pb = NSPasteboard.general

            // Stop accessing previously copied URLs
            for url in MenuActionTarget.copiedURLs {
                url.stopAccessingSecurityScopedResource()
            }
            MenuActionTarget.copiedURLs.removeAll()

            pb.clearContents()
            Task {
                let fileURLs = await selected.asyncCompactMap { item -> URL? in
                    if case .file = item.kind {
                        return await ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item)
                    }
                    return nil
                }
                if !fileURLs.isEmpty {
                    // Start security-scoped access for all URLs and keep them active
                    MenuActionTarget.copiedURLs = fileURLs.filter { $0.startAccessingSecurityScopedResource() }
                    NSLog("🔐 Started security-scoped access for \(MenuActionTarget.copiedURLs.count) copied files")

                    // Write to pasteboard
                    pb.writeObjects(fileURLs as [NSURL])
                } else {
                    let strings = selected.map { $0.displayName }
                    if !strings.isEmpty {
                        pb.setString(strings.joined(separator: "\n"), forType: .string)
                    }
                }
            }

        case .remove?:
            let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
            for it in selected { ShelfActionService.remove(it) }

        case .removeBackground?:
            handleRemoveBackground()

        case .convertImage?:
            showConvertImageDialog()

        case .createPDF?:
            handleCreatePDF()

        case .compress?:
            let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
            Task {
                let fileURLs = await resolveFileURLs(for: selected)
                guard !fileURLs.isEmpty else { return }
                // Create ZIP in a temporary location while holding access to selected resources
                if let zipTempURL = await fileURLs.accessSecurityScopedResources(accessor: { urls in
                    await TemporaryFileStorageService.shared.createZip(from: urls)
                }) {
                    if let bookmark = try? Bookmark(url: zipTempURL) {
                        let newItem = ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: true)
                        ShelfStateViewModel.shared.add([newItem])
                    } else {
                        // Fallback: reveal the temporary file in Finder
                        NSWorkspace.shared.activateFileViewerSelecting([zipTempURL])
                    }
                }
            }

        case .none:
            break
        }
    }

    @MainActor
    private func resolveFileURLs(for items: [ShelfItem]) async -> [URL] {
        await ShelfStateViewModel.shared.resolveFileURLs(for: items)
    }

    @MainActor
    private func resolveURLs(for items: [ShelfItem]) async -> [URL] {
        var urls: [URL] = []
        for item in items {
            guard let selectedItem = shelfState.items.first(where: { $0.id == item.id }) else { continue }
            switch selectedItem.kind {
            case .file:
                if let file = await shelfState.resolveFile(
                    for: selectedItem,
                    intent: .userInitiated,
                    refresh: true
                ) {
                    urls.append(file.url)
                }
            case .link(let url):
                urls.append(url)
            case .text:
                break
            }
        }
        return urls
    }

    @MainActor
    private func resolveImageURLs(for items: [ShelfItem]) async -> [URL] {
        var urls: [URL] = []
        for selectedItem in items {
            guard case .file = selectedItem.kind,
                  let file = await ShelfStateViewModel.shared.resolveFile(
                      for: selectedItem,
                      intent: .userInitiated,
                      refresh: true
                  ),
                  file.contentTypeIdentifier.flatMap(UTType.init)?.conforms(to: .image) == true else {
                continue
            }
            urls.append(file.url)
        }
        return urls
    }

    @MainActor
    private func openWithPanel() {
        Task { await showOpenWithPanel() }
    }

    @MainActor
    private func showOpenWithPanel() async {
        // Support both file items and link items
        let targetURL: URL?
        let needsSecurityScope: Bool
        let contentType: UTType?

        if case .file = item.kind {
            let file = await ShelfStateViewModel.shared.resolveFile(
                for: item,
                intent: .userInitiated,
                refresh: true
            )
            targetURL = file?.url
            needsSecurityScope = true
            contentType = file?.contentTypeIdentifier.flatMap(UTType.init)
        } else if case .link(let url) = item.kind {
            targetURL = url
            needsSecurityScope = false
            contentType = nil
        } else {
            targetURL = nil
            needsSecurityScope = false
            contentType = nil
        }
        guard let fileURL = targetURL else { return }

        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Application")
        panel.message = String(format: String(localized: "Choose an application to open the document \"%@\"."), item.displayName)
        panel.prompt = String(localized: "Open")
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.application]
        }
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        // Compute recommended applications for the selected target
        let recommendedApps = await Task.detached(priority: .userInitiated) {
            let applications: [URL]
            if let contentType {
                applications = NSWorkspace.shared.urlsForApplications(toOpen: contentType)
            } else {
                applications = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
            }
            return Set(applications.map(\.standardizedFileURL))
        }.value

        // Delegate to filter entries when in "Recommended Applications" mode
        final class AppChooserDelegate: NSObject, NSOpenSavePanelDelegate {
            enum Mode { case recommended, all }
            var mode: Mode = .recommended
            let recommended: Set<URL>
            init(recommended: Set<URL>) { self.recommended = recommended }

            func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
                let ext = url.pathExtension.lowercased()
                if ext == "app" {
                    switch mode {
                    case .all:
                        return true
                    case .recommended:
                        // Standardize URLs for reliable comparison
                        let std = url.standardizedFileURL
                        return recommended.contains(std)
                    }
                }

                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return true
                }

                return false
            }
        }

        let chooserDelegate = AppChooserDelegate(recommended: recommendedApps)
        panel.delegate = chooserDelegate

        let enableLabel = NSTextField(labelWithString: String(localized: "Enable:"))
        enableLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        enableLabel.alignment = .natural
        enableLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: [String(localized: "Recommended Applications"), String(localized: "All Applications")])
        popup.font = .systemFont(ofSize: NSFont.systemFontSize)
        popup.selectItem(at: 0)

        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        let alwaysCheckbox = NSButton(checkboxWithTitle: String(localized: "Always Open With"), target: nil, action: nil)
        alwaysCheckbox.font = .systemFont(ofSize: NSFont.systemFontSize)
        alwaysCheckbox.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [enableLabel, popup])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.distribution = .fill

        let column = NSStackView(views: [row, alwaysCheckbox])
        column.orientation = .vertical
        column.spacing = 12
        column.alignment = .centerX
        column.distribution = .fill
        column.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)

        panel.accessoryView = column
        panel.isAccessoryViewDisclosed = true

        // Wire up popup to switch filter mode
        class PopupBinder: NSObject {
            weak var popup: NSPopUpButton?
            weak var chooserDelegate: AppChooserDelegate?
            weak var panel: NSOpenPanel?
            init(popup: NSPopUpButton, chooserDelegate: AppChooserDelegate, panel: NSOpenPanel) {
                self.popup = popup
                self.chooserDelegate = chooserDelegate
                self.panel = panel
            }
            @MainActor @objc func changed(_ sender: Any?) {
                if popup?.indexOfSelectedItem == 1 {
                    chooserDelegate?.mode = .all
                } else {
                    chooserDelegate?.mode = .recommended
                }
                if let panel = panel {
                    panel.validateVisibleColumns()
                    let currentDir = panel.directoryURL
                    panel.directoryURL = currentDir
                }
            }
        }
        let binder = PopupBinder(popup: popup, chooserDelegate: chooserDelegate, panel: panel)
        popup.target = binder
        popup.action = #selector(PopupBinder.changed(_:))

        panel.begin { response in
            if response == .OK, let appURL = panel.url {
                Task {
                    do {
                        let config = NSWorkspace.OpenConfiguration()
                        if alwaysCheckbox.state == .on, let bundleID = Bundle(url: appURL)?.bundleIdentifier {
                            if let contentType {
                                let status = LSSetDefaultRoleHandlerForContentType(contentType.identifier as CFString, LSRolesMask.all, bundleID as CFString)
                                if status != noErr { Log.shelf.error("Failed to set default handler for \(contentType.identifier): \(status)") }
                            } else if let scheme = fileURL.scheme {
                                let status = LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleID as CFString)
                                if status != noErr { Log.shelf.error("Failed to set default handler for scheme \(scheme): \(status)") }
                            }
                        }

                        if needsSecurityScope {
                            _ = try await fileURL.accessSecurityScopedResource { accessibleURL in
                                try await NSWorkspace.shared.open([accessibleURL], withApplicationAt: appURL, configuration: config)
                            }
                        } else {
                            try await NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config)
                        }
                    } catch {
                        Log.shelf.error("❌ Failed to open with application: \(error.localizedDescription)")
                    }
                }
            }
            // Keep binder/delegate alive until panel finishes
            _ = binder
            _ = chooserDelegate
        }
    }

    @MainActor
    private func showRenameDialog(for item: ShelfItem) {
        guard case .file = item.kind else { return }
        Task {
            guard let file = await ShelfStateViewModel.shared.resolveFile(
                for: item,
                intent: .userInitiated,
                refresh: true
            ) else { return }
            let fileURL = file.url
            let savePanel = NSSavePanel()
            savePanel.title = String(localized: "Rename File")
            savePanel.prompt = String(localized: "Rename")
            savePanel.nameFieldStringValue = fileURL.lastPathComponent
            savePanel.directoryURL = fileURL.deletingLastPathComponent()
            savePanel.begin { response in
                guard response == .OK, let newURL = savePanel.url else { return }
                Task {
                    let result = await Task.detached(priority: .userInitiated) { () -> (Data?, String?) in
                        let didStart = fileURL.startAccessingSecurityScopedResource()
                        defer {
                            if didStart { fileURL.stopAccessingSecurityScopedResource() }
                        }
                        do {
                            try FileManager.default.moveItem(at: fileURL, to: newURL)
                            return ((try? Bookmark(url: newURL).data), nil)
                        } catch {
                            return (nil, error.localizedDescription)
                        }
                    }.value
                    if let bookmarkData = result.0 {
                        ShelfStateViewModel.shared.updateBookmark(for: item, bookmark: bookmarkData)
                    } else if let message = result.1 {
                        Log.shelf.error("❌ Failed to rename file: \(message)")
                    }
                }
            }
        }
    }

    @MainActor
    private func handleRemoveBackground() {
        let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
        Task {
            guard let imageURL = await resolveImageURLs(for: selected).first else { return }
            do {
                let resultURL = try await imageURL.accessSecurityScopedResource { url in
                    try await ImageProcessingService.shared.removeBackground(from: url)
                }

                if let resultURL = resultURL {
                    // Create bookmark and add to shelf as temporary item
                    if let bookmark = try? Bookmark(url: resultURL) {
                        let newItem = ShelfItem(
                            kind: .file(bookmark: bookmark.data),
                            isTemporary: true
                        )
                        ShelfStateViewModel.shared.add([newItem])
                    }
                }
            } catch {
                Log.shelf.error("❌ Failed to remove background: \(error.localizedDescription)")
                showErrorAlert(title: String(localized: "Background Removal Failed"), message: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func handleCreatePDF() {
        let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
        Task {
            let imageURLs = await resolveImageURLs(for: selected)
            guard !imageURLs.isEmpty else { return }
            do {
                let resultURL = try await imageURLs.accessSecurityScopedResources { urls in
                    try await ImageProcessingService.shared.createPDF(from: urls)
                }

                if let resultURL = resultURL {
                    // Create bookmark and add to shelf as temporary item
                    if let bookmark = try? Bookmark(url: resultURL) {
                        let newItem = ShelfItem(
                            kind: .file(bookmark: bookmark.data),
                            isTemporary: true
                        )
                        ShelfStateViewModel.shared.add([newItem])
                    }
                }
            } catch {
                Log.shelf.error("❌ Failed to create PDF: \(error.localizedDescription)")
                showErrorAlert(title: String(localized: "PDF Creation Failed"), message: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func showConvertImageDialog() {
        let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
        Task {
            guard let imageURL = await resolveImageURLs(for: selected).first else { return }
            presentConvertImageDialog(for: imageURL)
        }
    }

    @MainActor
    private func presentConvertImageDialog(for imageURL: URL) {
        
        // Create and show conversion options dialog with better layout
        let alert = NSAlert()
        alert.messageText = String(localized: "Convert Image")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Convert"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        // Create accessory view with better spacing and organization
        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 180))
        accessoryView.wantsLayer = true

        // MARK: Format Row
        let formatLabel = NSTextField(labelWithString: String(localized: "Format:"))
        formatLabel.frame = NSRect(x: 0, y: 145, width: 100, height: 20)
        formatLabel.font = .systemFont(ofSize: 12, weight: .medium)
        accessoryView.addSubview(formatLabel)

        let formatPopup = NSPopUpButton(frame: NSRect(x: 120, y: 140, width: 250, height: 28))
        formatPopup.addItems(withTitles: ["PNG", "JPEG", "HEIC", "TIFF", "BMP"])
        formatPopup.selectItem(at: 0)
        formatPopup.font = .systemFont(ofSize: 12)
        accessoryView.addSubview(formatPopup)

        // MARK: Image Size Row
        let imageSizeLabel = NSTextField(labelWithString: String(localized: "Image Size:"))
        imageSizeLabel.frame = NSRect(x: 0, y: 105, width: 100, height: 20)
        imageSizeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        accessoryView.addSubview(imageSizeLabel)

        let imageSizePopup = NSPopUpButton(frame: NSRect(x: 120, y: 100, width: 160, height: 28))
        imageSizePopup.addItems(withTitles: [String(localized: "Actual Size"), String(localized: "Large"), String(localized: "Medium"), String(localized: "Small"), String(localized: "Custom…")])
        imageSizePopup.selectItem(at: 0)
        imageSizePopup.font = .systemFont(ofSize: 12)
        accessoryView.addSubview(imageSizePopup)

        // Custom size field (initially hidden)
        let customSizeField = NSTextField(frame: NSRect(x: 285, y: 103, width: 85, height: 22))
        customSizeField.placeholderString = String(localized: "e.g., 1920")
        customSizeField.font = .systemFont(ofSize: 12)
        customSizeField.isHidden = true
        accessoryView.addSubview(customSizeField)

        // MARK: Preserve Metadata Checkbox
        let metadataCheckbox = NSButton(checkboxWithTitle: String(localized: "Preserve Metadata"), target: nil, action: nil)
        metadataCheckbox.frame = NSRect(x: 120, y: 65, width: 200, height: 20)
        metadataCheckbox.font = .systemFont(ofSize: 12)
        metadataCheckbox.state = .on
        accessoryView.addSubview(metadataCheckbox)

        // MARK: Separator line
        let separatorLine = NSView(frame: NSRect(x: 0, y: 50, width: 380, height: 1))
        separatorLine.wantsLayer = true
        separatorLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        accessoryView.addSubview(separatorLine)

        // MARK: Format-specific options (shown/hidden based on format selection)
        let qualityRow = NSView(frame: NSRect(x: 0, y: 15, width: 380, height: 30))
        qualityRow.wantsLayer = true

        let qualityLabel = NSTextField(labelWithString: String(localized: "Compression:"))
        qualityLabel.frame = NSRect(x: 0, y: 7, width: 100, height: 20)
        qualityLabel.font = .systemFont(ofSize: 12, weight: .medium)
        qualityRow.addSubview(qualityLabel)

        let qualitySlider = NSSlider(frame: NSRect(x: 120, y: 12, width: 200, height: 20))
        qualitySlider.minValue = 0.0
        qualitySlider.maxValue = 1.0
        qualitySlider.doubleValue = 0.85
        accessoryView.addSubview(qualitySlider)

        let qualityValueLabel = NSTextField(labelWithString: 0.85.formatted(.percent.precision(.fractionLength(0))))
        qualityValueLabel.frame = NSRect(x: 325, y: 7, width: 55, height: 20)
        qualityValueLabel.font = .systemFont(ofSize: 12)
        qualityValueLabel.alignment = .natural
        accessoryView.addSubview(qualityValueLabel)

        // Update quality label and hide/show compression row based on format
        let updateQualityLabel = {
            qualityValueLabel.stringValue = qualitySlider.doubleValue.formatted(.percent.precision(.fractionLength(0)))
        }

        let updateCompressionVisibility = {
            let formatIndex = formatPopup.indexOfSelectedItem
            let showCompression = formatIndex == 1 || formatIndex == 2 // JPEG or HEIC
            qualitySlider.isHidden = !showCompression
            qualityValueLabel.isHidden = !showCompression
            qualityLabel.isHidden = !showCompression
        }

        let updateCustomSizeVisibility = {
            let sizeIndex = imageSizePopup.indexOfSelectedItem
            customSizeField.isHidden = sizeIndex != 4 // Show only for "Custom..."
        }

        // Create a target object to handle slider value changes
        class SliderHandler: NSObject {
            let updateLabel: () -> Void
            let updateVisibility: () -> Void
            let updateCustomSize: () -> Void
            init(updateLabel: @escaping () -> Void, updateVisibility: @escaping () -> Void, updateCustomSize: @escaping () -> Void) {
                self.updateLabel = updateLabel
                self.updateVisibility = updateVisibility
                self.updateCustomSize = updateCustomSize
            }
            @objc func sliderChanged(_ sender: NSSlider) {
                updateLabel()
            }
            @objc func formatChanged(_ sender: NSPopUpButton) {
                updateVisibility()
            }
            @objc func sizeChanged(_ sender: NSPopUpButton) {
                updateCustomSize()
            }
        }

        let handler = SliderHandler(updateLabel: updateQualityLabel, updateVisibility: updateCompressionVisibility, updateCustomSize: updateCustomSizeVisibility)
        qualitySlider.target = handler
        qualitySlider.action = #selector(SliderHandler.sliderChanged(_:))
        qualitySlider.isContinuous = true

        formatPopup.target = handler
        formatPopup.action = #selector(SliderHandler.formatChanged(_:))

        imageSizePopup.target = handler
        imageSizePopup.action = #selector(SliderHandler.sizeChanged(_:))

        updateCompressionVisibility()
        updateQualityLabel()
        updateCustomSizeVisibility()

        // Keep the handler alive using the `AssociatedObject` helper instead of a magic string key
        MenuActionTarget.sliderHandlerAssoc[accessoryView] = handler

        alert.accessoryView = accessoryView

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Get selected options
            let formatIndex = formatPopup.indexOfSelectedItem
            let format: ImageConversionOptions.ImageFormat
            switch formatIndex {
            case 0: format = .png
            case 1: format = .jpeg
            case 2: format = .heic
            case 3: format = .tiff
            case 4: format = .bmp
            default: format = .png
            }

            let quality = qualitySlider.doubleValue

            // Get max dimension based on image size selection
            let maxDimension: CGFloat? = {
                let sizeIndex = imageSizePopup.indexOfSelectedItem
                switch sizeIndex {
                case 0: return nil // Actual Size
                case 1: return 1280 // Large 
                case 2: return 640  // Medium 
                case 3: return 320  // Small 
                case 4: // Custom (user-specified)
                    let text = customSizeField.stringValue.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty, let value = Double(text), value > 0 else { return nil }
                    return CGFloat(value)
                default: return nil
                }
            }()

            let removeMetadata = metadataCheckbox.state == .off // Note: we invert this

            let options = ImageConversionOptions(
                format: format,
                compressionQuality: quality,
                maxDimension: maxDimension,
                removeMetadata: removeMetadata
            )

            Task {
                do {
                    let resultURL = try await imageURL.accessSecurityScopedResource { url in
                        try await ImageProcessingService.shared.convertImage(from: url, options: options)
                    }

                    if let resultURL = resultURL {
                        // Create bookmark and add to shelf as temporary item
                        if let bookmark = try? Bookmark(url: resultURL) {
                            let newItem = ShelfItem(
                                kind: .file(bookmark: bookmark.data),
                                isTemporary: true
                            )
                            ShelfStateViewModel.shared.add([newItem])
                        }
                    }
                } catch {
                    Log.shelf.error("❌ Failed to convert image: \(error.localizedDescription)")
                    showErrorAlert(title: String(localized: "Image Conversion Failed"), message: error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}

fileprivate extension Sequence {
    func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var result: [T] = []
        for element in self {
            if let transformed = await transform(element) {
                result.append(transformed)
            }
        }
        return result
    }
}
