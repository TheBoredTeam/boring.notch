//
//  ShelfItemViewModel.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreServices

@MainActor
final class ShelfItemViewModel: ObservableObject {
    @Published private(set) var item: ShelfItem
    @Published var thumbnail: NSImage?
    @Published var isDropTargeted: Bool = false
    @Published var isRenaming: Bool = false
    @Published var draftTitle: String = ""
    private var sharingLifecycle: SharingLifecycleDelegate?
    private var quickShareLifecycle: SharingLifecycleDelegate?
    private var sharingAccessingURLs: [URL] = []

    private let selection = ShelfSelectionModel.shared

    init(item: ShelfItem) {
        self.item = item
        self.draftTitle = item.displayName
        Task { await loadThumbnail() }
    }

    var isSelected: Bool { selection.isSelected(item.id) }

    func loadThumbnail() async {
        guard let url = item.fileURL else { return }
        if let image = await ThumbnailService.shared.thumbnail(for: url, size: CGSize(width: 56, height: 56)) {
            self.thumbnail = image
        }
    }

    // MARK: - Drag & Drop helpers
    func dragItemProvider() -> NSItemProvider {
    let selectedItems = selection.selectedItems(in: ShelfStateViewModel.shared.items)
        if selectedItems.count > 1 && selectedItems.contains(where: { $0.id == item.id }) {
            return createMultiItemProvider(for: selectedItems)
        }
        return createItemProvider(for: item)
    }

    private func createItemProvider(for item: ShelfItem) -> NSItemProvider {
        switch item.kind {
        case .file:
            let provider = NSItemProvider()
            Task {
                // Use immediate update for user-initiated drag operation
                if let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) {
                    provider.registerObject(url as NSURL, visibility: .all)
                } else {
                    provider.registerObject(item.displayName as NSString, visibility: .all)
                }
            }
            return provider
        case .text(let string):
            return NSItemProvider(object: string as NSString)
        case .link(let url):
            return NSItemProvider(object: url as NSURL)
        }
    }

    private func createMultiItemProvider(for items: [ShelfItem]) -> NSItemProvider {
        let provider = NSItemProvider()
        Task {
            var urls: [URL] = []
            var textItems: [String] = []
            for item in items {
                switch item.kind {
                case .file:
                    // Use immediate update for user-initiated drag operation
                    if let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) {
                        urls.append(url)
                    } else {
                        textItems.append(item.displayName)
                    }
                case .text(let string):
                    textItems.append(string)
                case .link:
                    break
                }
            }
            if !urls.isEmpty {
                for url in urls {
                    provider.registerObject(url as NSURL, visibility: .all)
                }
            }
            if !textItems.isEmpty {
                provider.registerObject(textItems.joined(separator: "\n") as NSString, visibility: .all)
            }
        }
        return provider
    }

    // MARK: - Actions
    func handleClick(event: NSEvent, view: NSView) {
        let flags = event.modifierFlags
        if flags.contains(.shift) {
            selection.shiftSelect(to: item, in: ShelfStateViewModel.shared.items)
        } else if flags.contains(.command) {
            selection.toggle(item)
        } else if flags.contains(.control) {
            handleRightClick(event: event, view: view)
        } else {
            if !selection.isSelected(item.id) { selection.selectSingle(item) }
        }
        if event.clickCount == 2 { handleDoubleClick() }
    }

    func handleRightClick(event: NSEvent, view: NSView) {
        if !selection.isSelected(item.id) { selection.selectSingle(item) }
        presentContextMenu(event: event, in: view)
    }

    func handleDoubleClick() {
    let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
        for it in selected { ShelfActionService.open(it) }
    }

    func shareItem(from view: NSView?) {
        Task {
            var itemsToShare: [Any] = []
            var fileURLs: [URL] = []
            if case .text(let text) = item.kind {
                itemsToShare.append(text)
            } else {
                for item in ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items) {
                    switch item.kind {
                    case .file:
                        // Use immediate update for user-initiated share action
                        if let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) {
                            itemsToShare.append(url)
                            fileURLs.append(url)
                        }
                    case .text(let string):
                        itemsToShare.append(string)
                    case .link(let url):
                        itemsToShare.append(url)
                    }
                }
            }
            
            guard !itemsToShare.isEmpty else { return }
             
            stopSharingAccessingURLs()
            // Start security-scoped access for all file URLs and keep it active during sharing
            sharingAccessingURLs = fileURLs.filter { $0.startAccessingSecurityScopedResource() }
            
            // Create and retain lifecycle delegate for the entire share operation
            let lifecycle = SharingStateManager.shared.makeDelegate { [weak self] in
                self?.sharingLifecycle = nil
                self?.stopSharingAccessingURLs()
            }
            self.sharingLifecycle = lifecycle
            
            let picker = NSSharingServicePicker(items: itemsToShare)
            picker.delegate = lifecycle
            lifecycle.markPickerBegan()
            if let view {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        }
    }
    
    private func stopSharingAccessingURLs() {
        for url in sharingAccessingURLs {
            url.stopAccessingSecurityScopedResource()
        }
        sharingAccessingURLs.removeAll()
    }

    /// Call this closure to request a QuickLook preview for the given URLs.
    var onQuickLookRequest: (([URL]) -> Void)?

    // MARK: - Context Menu helpers (extracted from view)
    func loadOpenWithApps() -> [URL] {
        // Support both files and link items. For link items we ask NSWorkspace for apps that can open the URL (browsers).
        if let fileURL = item.fileURL {
            var results: [URL] = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
            if results.isEmpty {
                if let uti = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
                    results = NSWorkspace.shared.urlsForApplications(toOpen: uti)
                }
            }
            let unique = Array(Set(results))
            let sorted = unique.sorted { appDisplayName(for: $0) < appDisplayName(for: $1) }
            return sorted
        } else if case .link(let url) = item.kind {
            var results: [URL] = NSWorkspace.shared.urlsForApplications(toOpen: url)
            if results.isEmpty {
                if let uti = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
                    results = NSWorkspace.shared.urlsForApplications(toOpen: uti)
                }
            }
            let unique = Array(Set(results))
            let sorted = unique.sorted { appDisplayName(for: $0) < appDisplayName(for: $1) }
            return sorted
        }
        return []
    }

    private func ensureContextMenuSelection() {
        if !selection.isSelected(item.id) { selection.selectSingle(item) }
    }

    func presentContextMenu(event: NSEvent, in view: NSView) {
        ensureContextMenuSelection()
        let menu = NSMenu()

        func addMenuItem(title: String) {
            let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            menu.addItem(mi)
        }

    let selectedItems = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
        // URLs that are valid targets for "Open With" (files or link URLs)
        let selectedOpenWithURLs = selectedItems.compactMap { itm -> URL? in
            if let u = itm.fileURL { return u }
            if case .link(let url) = itm.kind { return url }
            return nil
        }

        let selectedFileURLs = selectedItems.compactMap { $0.fileURL }

        addMenuItem(title: "Open")

        if !selectedOpenWithURLs.isEmpty {
            let openWith = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            let submenu = NSMenu()

            let openWithApps = loadOpenWithApps()
            let defaultApp = defaultAppURL()

            if openWithApps.isEmpty {
                let noApps = NSMenuItem(title: "No Compatible Apps Found", action: nil, keyEquivalent: "")
                noApps.isEnabled = false
                submenu.addItem(noApps)
            } else {
                if let defaultApp = defaultApp {
                    let appName = appDisplayName(for: defaultApp)
                    let def = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
                    def.representedObject = defaultApp
                    def.image = nsAppIcon(for: defaultApp, size: 16)

                    let title = NSMutableAttributedString(string: appName, attributes: [
                        .font: NSFont.menuFont(ofSize: 0),
                        .foregroundColor: NSColor.labelColor
                    ])
                    let defaultPart = NSAttributedString(string: " (default)", attributes: [
                        .font: NSFont.menuFont(ofSize: 0),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ])
                    title.append(defaultPart)
                    def.attributedTitle = title
                    submenu.addItem(def)

                    if openWithApps.count > 1 || !openWithApps.contains(defaultApp) {
                        submenu.addItem(NSMenuItem.separator())
                    }
                }
                for appURL in openWithApps where appURL != defaultApp {
                    let mi = NSMenuItem(title: appDisplayName(for: appURL), action: nil, keyEquivalent: "")
                    mi.representedObject = appURL
                    mi.image = nsAppIcon(for: appURL, size: 16)
                    submenu.addItem(mi)
                }
            }

            submenu.addItem(NSMenuItem.separator())
            let other = NSMenuItem(title: "Other…", action: nil, keyEquivalent: "")
            other.representedObject = "__OTHER__"
            submenu.addItem(other)

            openWith.submenu = submenu
            menu.addItem(openWith)
        }

        if !selectedFileURLs.isEmpty { addMenuItem(title: "Show in Finder") }
        if !selectedOpenWithURLs.isEmpty { 
            // Add Quick Look menu item
            let quickLookItem = NSMenuItem(title: "Quick Look", action: nil, keyEquivalent: "")
            menu.addItem(quickLookItem)
            
            // Add Slideshow as alternate menu item (shown when Option key is held)
            let slideshowItem = NSMenuItem(title: "Quick Look", action: nil, keyEquivalent: "")
            slideshowItem.isAlternate = true
            slideshowItem.keyEquivalentModifierMask = [.option]
            menu.addItem(slideshowItem)
        }

        menu.addItem(NSMenuItem.separator())
        addMenuItem(title: "Share…")

        if selectedItems.count == 1, case .file(_) = item.kind { addMenuItem(title: "Rename") }

        // Always show "Copy" for all item types
        addMenuItem(title: "Copy")
        // If there are file URLs, add "Copy Path" as an alternate menu item (Option key)
        if !selectedFileURLs.isEmpty {
            let copyPathItem = NSMenuItem(title: "Copy Path", action: nil, keyEquivalent: "")
            copyPathItem.isAlternate = true
            copyPathItem.keyEquivalentModifierMask = [.option]
            menu.addItem(copyPathItem)
        }

        menu.addItem(NSMenuItem.separator())
        addMenuItem(title: "Remove")

        let actionTarget = MenuActionTarget(item: item, view: view, viewModel: self)

        for menuItem in menu.items {
            if menuItem.isSeparatorItem { continue }
            menuItem.target = actionTarget
            menuItem.action = #selector(MenuActionTarget.handle(_:))

            if let submenu = menuItem.submenu {
                for subItem in submenu.items {
                    if !subItem.isSeparatorItem {
                        subItem.target = actionTarget
                        subItem.action = #selector(MenuActionTarget.handle(_:))
                    }
                }
            }
        }
        
        menu.retainActionTarget(actionTarget)
        
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private final class MenuActionTarget: NSObject {
        let item: ShelfItem
        weak var view: NSView?
        unowned let viewModel: ShelfItemViewModel

        init(item: ShelfItem, view: NSView, viewModel: ShelfItemViewModel) {
            self.item = item
            self.view = view
            self.viewModel = viewModel
        }

        @MainActor @objc func handle(_ sender: NSMenuItem) {
            let title = sender.title

            if let marker = sender.representedObject as? String, marker == "__OTHER__" {
                openWithPanel()
                return
            }

            if let appURL = sender.representedObject as? URL {
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                
                Task {
                        var allSelectedURLs: [URL] = []

                        for itm in selected {
                            if let fileURL = itm.fileURL {
                                allSelectedURLs.append(fileURL)
                            } else if case .link(let url) = itm.kind {
                                allSelectedURLs.append(url)
                            }
                        }

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
                            print("❌ Failed to open with application: \(error.localizedDescription)")
                        }
                }
                return
            }

            switch title {
            case "Quick Look":
                // Handle all selected items for Quick Look, not just the clicked item
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                let urls: [URL] = selected.compactMap { item in
                    if let fileURL = item.fileURL {
                        return fileURL
                    }
                    if case .link(let url) = item.kind {
                        return url
                    }
                    return nil
                }
                if !urls.isEmpty {
                    viewModel.onQuickLookRequest?(urls)
                }

            case "Open":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                for it in selected { ShelfActionService.open(it) }

            case "Share…":
                viewModel.shareItem(from: view)

            case "Rename":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                if selected.count == 1, let single = selected.first { showRenameDialog(for: single) }

            case "Show in Finder":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                Task {
                    let urls = await selected.asyncCompactMap { item -> URL? in
                        if case .file = item.kind {
                            // Use immediate update for user-initiated menu action
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

            case "Copy Path":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                let paths = selected.compactMap { $0.fileURL?.path }
                if !paths.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
                }

            case "Copy":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                let pb = NSPasteboard.general
                pb.clearContents()
                Task {
                    let fileURLs = await selected.asyncCompactMap { item -> URL? in
                        if case .file = item.kind {
                            return ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item)
                        }
                        return nil
                    }
                    if !fileURLs.isEmpty {
                        await fileURLs.accessSecurityScopedResources { accessibleURLs in
                            pb.writeObjects(accessibleURLs as [NSURL])
                        }
                    } else {
                        let strings = selected.map { $0.displayName }
                        if !strings.isEmpty {
                            pb.setString(strings.joined(separator: "\n"), forType: .string)
                        }
                    }
                }

            case "Remove":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                for it in selected { ShelfActionService.remove(it) }
            default:
                break
            }
        }

        @MainActor
        private func openWithPanel() {
            // Support both file items and link items
            let targetURL: URL?
            let needsSecurityScope: Bool
            
            if let fileURL = item.fileURL {
                targetURL = fileURL
                needsSecurityScope = true
            } else if case .link(let url) = item.kind {
                targetURL = url
                needsSecurityScope = false
            } else {
                targetURL = nil
                needsSecurityScope = false
            }
            guard let fileURL = targetURL else { return }

            let panel = NSOpenPanel()
            panel.title = "Choose Application"
            panel.message = "Choose an application to open the document \"\(item.displayName)\"."
            panel.prompt = "Open"
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.resolvesAliases = true
            if #available(macOS 12.0, *) {
                panel.allowedContentTypes = [.application]
            }
            panel.directoryURL = URL(fileURLWithPath: "/Applications")

            // Compute recommended applications for the selected target
            let recommendedApps: Set<URL> = {
                let apps: [URL]
                if let uti = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
                    apps = NSWorkspace.shared.urlsForApplications(toOpen: uti)
                } else {
                    apps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
                }
                return Set(apps.map { $0.standardizedFileURL })
            }()

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

            let enableLabel = NSTextField(labelWithString: "Enable:")
            enableLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
            enableLabel.alignment = .natural
            enableLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: ["Recommended Applications", "All Applications"])
            popup.font = .systemFont(ofSize: NSFont.systemFontSize)
            popup.selectItem(at: 0)
            
            popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
            
            let alwaysCheckbox = NSButton(checkboxWithTitle: "Always Open With", target: nil, action: nil)
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
                @objc func changed(_ sender: Any?) {
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
                                if let contentType = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
                                    let status = LSSetDefaultRoleHandlerForContentType(contentType.identifier as CFString, LSRolesMask.all, bundleID as CFString)
                                    if status != noErr { print("⚠️ Failed to set default handler for \(contentType.identifier): \(status)") }
                                } else if let scheme = fileURL.scheme {
                                    let status = LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleID as CFString)
                                    if status != noErr { print("⚠️ Failed to set default handler for scheme \(scheme): \(status)") }
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
                            print("❌ Failed to open with application: \(error.localizedDescription)")
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
            guard case let .file(bookmarkData) = item.kind else { return }
            Task {
                let bookmark = Bookmark(data: bookmarkData)
                if let fileURL = bookmark.resolveURL() {
                    // Start security-scoped access and keep it active until rename completes.
                    let didStart = fileURL.startAccessingSecurityScopedResource()

                    let savePanel = NSSavePanel()
                    savePanel.title = "Rename File"
                    savePanel.prompt = "Rename"
                    savePanel.nameFieldStringValue = fileURL.lastPathComponent
                    savePanel.directoryURL = fileURL.deletingLastPathComponent()
                    savePanel.begin { response in
                        if response == .OK, let newURL = savePanel.url {
                            Task {
                                do {
                                    NSLog("🔐 Rename: moving from \(fileURL.path) to \(newURL.path) (securityScope=\(didStart))")

                                    try FileManager.default.moveItem(at: fileURL, to: newURL)

                                    if let newBookmark = try? Bookmark(url: newURL) {
                                        ShelfStateViewModel.shared.updateBookmark(for: item, bookmark: newBookmark.data)
                                    }
                                } catch {
                                    print("❌ Failed to rename file: \(error.localizedDescription)")
                                }
                                if didStart { fileURL.stopAccessingSecurityScopedResource() }
                            }
                        } else {
                            if didStart { fileURL.stopAccessingSecurityScopedResource() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private helpers
    private func appDisplayName(for appURL: URL) -> String {
        (try? appURL.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? appURL.lastPathComponent
    }

    private func nsAppIcon(for appURL: URL, size: CGFloat) -> NSImage? {
        let baseIcon = NSWorkspace.shared.icon(forFile: appURL.path)
        baseIcon.isTemplate = false

        let targetSize = NSSize(width: size, height: size)
        let rendered = NSImage(size: targetSize, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            baseIcon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: [
                .interpolation: NSImageInterpolation.high.rawValue
            ])
            return true
        }

        rendered.size = targetSize
        return rendered
    }

    private func defaultAppURL() -> URL? {
        if let fileURL = item.fileURL {
            return NSWorkspace.shared.urlForApplication(toOpen: fileURL)
        } else if case .link(let url) = item.kind {
            return NSWorkspace.shared.urlForApplication(toOpen: url)
        }
        return nil
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
