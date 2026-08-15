//
//  ShelfContextMenu.swift
//  boringNotch
//
//  AppKit context-menu construction and action dispatch for shelf items.
//  Extracted from ShelfItemViewModel: the VM keeps item state and routes
//  clicks here. Behavior preserved verbatim.
//

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreServices
import ObjectiveC

// MARK: - Localization helpers
struct Strings {
    static let open = NSLocalizedString("Shelf.ContextMenu.Open", comment: "Context menu item: Open")
    static let openWith = NSLocalizedString("Shelf.ContextMenu.OpenWith", comment: "Context menu item: Open With")
    static let noCompatibleApps = NSLocalizedString("Shelf.ContextMenu.NoCompatibleAppsFound", comment: "Context menu item: No Compatible Apps Found")
    static let other = NSLocalizedString("Shelf.ContextMenu.Other", comment: "Context menu item: Other…")
    static let showInFinder = NSLocalizedString("Shelf.ContextMenu.ShowInFinder", comment: "Context menu item: Show in Finder")
    static let quickLook = NSLocalizedString("Shelf.ContextMenu.QuickLook", comment: "Context menu item: Quick Look")
    static let share = NSLocalizedString("Shelf.ContextMenu.Share", comment: "Context menu item: Share…")
    static let imageActions = NSLocalizedString("Shelf.ContextMenu.ImageActions", comment: "Context menu item: Image Actions")
    static let removeBackground = NSLocalizedString("Shelf.ContextMenu.RemoveBackground", comment: "Context menu item: Remove Background")
    static let convertImage = NSLocalizedString("Shelf.ContextMenu.ConvertImage", comment: "Context menu item: Convert Image…")
    static let createPDF = NSLocalizedString("Shelf.ContextMenu.CreatePDF", comment: "Context menu item: Create PDF")
    static let compress = NSLocalizedString("Shelf.ContextMenu.Compress", comment: "Context menu item: Compress")
    static let rename = NSLocalizedString("Shelf.ContextMenu.Rename", comment: "Context menu item: Rename")
    static let copy = NSLocalizedString("Shelf.ContextMenu.Copy", comment: "Context menu item: Copy")
    static let copyPath = NSLocalizedString("Shelf.ContextMenu.CopyPath", comment: "Context menu item: Copy Path")
    static let remove = NSLocalizedString("Shelf.ContextMenu.Remove", comment: "Context menu item: Remove")
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
    let menu = NSMenu()

    func addMenuItem(title: String, contextAction: ContextMenuAction? = nil) {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let contextAction {
            mi.representedObject = contextAction.rawValue
        }
        menu.addItem(mi)
    }

    let selectedItems = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
    let selectedFileURLs = selectedItems.compactMap { $0.fileURL }
    let selectedLinkURLs: [URL] = selectedItems.compactMap { itm in
        if case .link(let url) = itm.kind { return url }
        return nil
    }
    let selectedFolderURLs = selectedFileURLs.filter { isDirectory($0) }
    // URLs valid for Open/Open With (exclude folders)
    let selectedOpenableURLs = selectedItems.compactMap { itm -> URL? in
        if let u = itm.fileURL { return isDirectory(u) ? nil : u }
        if case .link(let url) = itm.kind { return url }
        return nil
    }

    if !selectedOpenableURLs.isEmpty {
        addMenuItem(title: Strings.open, contextAction: .open)
    }

    if !selectedOpenableURLs.isEmpty {
        let openWith = NSMenuItem(title: Strings.openWith, action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        // Choose a representative URL to compute apps (prefer current item if not a folder)
        let baseURLForApps: URL? = {
            if let u = item.fileURL, !isDirectory(u) { return u }
            if case .link(let u) = item.kind { return u }
            return selectedOpenableURLs.first
        }()

        let openWithApps: [URL] = {
            guard let u = baseURLForApps else { return [] }
            if u.isFileURL {
                var results = NSWorkspace.shared.urlsForApplications(toOpen: u)
                if results.isEmpty, let uti = try? u.resourceValues(forKeys: [.contentTypeKey]).contentType {
                    results = NSWorkspace.shared.urlsForApplications(toOpen: uti)
                }
                return Array(Set(results))
            } else {
                return Array(Set(NSWorkspace.shared.urlsForApplications(toOpen: u)))
            }
        }()
        let defaultApp = defaultAppURL(for: item)

        if openWithApps.isEmpty {
            let noApps = NSMenuItem(title: Strings.noCompatibleApps, action: nil, keyEquivalent: "")
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
        let other = NSMenuItem(title: Strings.other, action: nil, keyEquivalent: "")
        other.representedObject = "__OTHER__"
        submenu.addItem(other)

        openWith.submenu = submenu
        menu.addItem(openWith)
    }

    if !selectedFileURLs.isEmpty { addMenuItem(title: Strings.showInFinder, contextAction: .showInFinder) }
    // Allow Quick Look for files and link URLs
    if !selectedFileURLs.isEmpty || !selectedLinkURLs.isEmpty {
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
    let imageURLs = selectedFileURLs.filter { ImageProcessingService.shared.isImageFile($0) }
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
    if !selectedFileURLs.isEmpty {
        let compressItem = NSMenuItem(title: Strings.compress, action: nil, keyEquivalent: "")
        compressItem.representedObject = ContextMenuAction.compress.rawValue
        menu.addItem(compressItem)
    }

    if selectedItems.count == 1, case .file(_) = item.kind { addMenuItem(title: Strings.rename, contextAction: .rename) }

    // Always show "Copy" for all item types
    addMenuItem(title: Strings.copy, contextAction: .copy)
    // If there are file URLs, add "Copy Path" as an alternate menu item (Option key)
    if !selectedFileURLs.isEmpty {
        let copyPathItem = NSMenuItem(title: Strings.copyPath, action: nil, keyEquivalent: "")
        copyPathItem.representedObject = ContextMenuAction.copyPath.rawValue
        copyPathItem.isAlternate = true
        copyPathItem.keyEquivalentModifierMask = [.option]
        menu.addItem(copyPathItem)
    }

    menu.addItem(NSMenuItem.separator())
    addMenuItem(title: Strings.remove, contextAction: .remove)

    let actionTarget = MenuActionTarget(item: item, view: view, onShare: onShare, onQuickLook: onQuickLook)

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
}

private func isDirectory(_ url: URL) -> Bool {
    url.accessSecurityScopedResource { scoped in
        (try? scoped.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}

func appDisplayName(for appURL: URL) -> String {
    (try? appURL.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? appURL.lastPathComponent
}

func nsAppIcon(for appURL: URL, size: CGFloat) -> NSImage? {
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

@MainActor
func defaultAppURL(for item: ShelfItem) -> URL? {
    if let fileURL = item.fileURL {
        return NSWorkspace.shared.urlForApplication(toOpen: fileURL)
    } else if case .link(let url) = item.kind {
        return NSWorkspace.shared.urlForApplication(toOpen: url)
    }
    return nil
}


private final class MenuActionTarget: NSObject {
    private static var copiedURLs: [URL] = []
    let item: ShelfItem
    weak var view: NSView?
    let onShare: (NSView?) -> Void
    let onQuickLook: ([URL]) -> Void

    // Keep associated objects (like accessory view handlers) without magic keys
    private static var sliderHandlerAssoc = AssociatedObject<AnyObject>()

    init(item: ShelfItem, view: NSView, onShare: @escaping (NSView?) -> Void, onQuickLook: @escaping ([URL]) -> Void) {
        self.item = item
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
                        Log.shelf.error("❌ Failed to open with application: \(error.localizedDescription)")
                    }
            }
            return
        }

        switch action {
        case .quickLook?:
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
                onQuickLook(urls)
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
                        // Use immediate update for user-initiated menu action
                        return ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item)
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
            let paths = selected.compactMap { $0.fileURL?.path }
            if !paths.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
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
                        return ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item)
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
            let fileURLs = selected.compactMap { $0.fileURL }
            guard !fileURLs.isEmpty else { break }

            Task {
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
                            if let contentType = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
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
        guard case let .file(bookmarkData) = item.kind else { return }
        Task {
            let bookmark = Bookmark(data: bookmarkData)
            if let fileURL = bookmark.resolvedURL {
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
                                Log.shelf.error("❌ Failed to rename file: \(error.localizedDescription)")
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
    
    @MainActor
    private func handleRemoveBackground() {
        let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
        let imageURLs = selected.compactMap { $0.fileURL }.filter { ImageProcessingService.shared.isImageFile($0) }
        
        guard let imageURL = imageURLs.first else { return }
        
        Task {
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
        let imageURLs = selected.compactMap { $0.fileURL }.filter { ImageProcessingService.shared.isImageFile($0) }
        
        guard !imageURLs.isEmpty else { return }
        
        Task {
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
        let imageURLs = selected.compactMap { $0.fileURL }.filter { ImageProcessingService.shared.isImageFile($0) }
        
        guard let imageURL = imageURLs.first else { return }
        
        // Create and show conversion options dialog with better layout
        let alert = NSAlert()
        alert.messageText = "Convert Image"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Convert")
        alert.addButton(withTitle: "Cancel")
        
        // Create accessory view with better spacing and organization
        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 180))
        accessoryView.wantsLayer = true
        
        // MARK: Format Row
        let formatLabel = NSTextField(labelWithString: "Format:")
        formatLabel.frame = NSRect(x: 0, y: 145, width: 100, height: 20)
        formatLabel.font = .systemFont(ofSize: 12, weight: .medium)
        accessoryView.addSubview(formatLabel)
        
        let formatPopup = NSPopUpButton(frame: NSRect(x: 120, y: 140, width: 250, height: 28))
        formatPopup.addItems(withTitles: ["PNG", "JPEG", "HEIC", "TIFF", "BMP"])
        formatPopup.selectItem(at: 0)
        formatPopup.font = .systemFont(ofSize: 12)
        accessoryView.addSubview(formatPopup)
        
        // MARK: Image Size Row
        let imageSizeLabel = NSTextField(labelWithString: "Image Size:")
        imageSizeLabel.frame = NSRect(x: 0, y: 105, width: 100, height: 20)
        imageSizeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        accessoryView.addSubview(imageSizeLabel)
        
        let imageSizePopup = NSPopUpButton(frame: NSRect(x: 120, y: 100, width: 160, height: 28))
        imageSizePopup.addItems(withTitles: ["Actual Size", "Large", "Medium", "Small", "Custom..."])
        imageSizePopup.selectItem(at: 0)
        imageSizePopup.font = .systemFont(ofSize: 12)
        accessoryView.addSubview(imageSizePopup)
        
        // Custom size field (initially hidden)
        let customSizeField = NSTextField(frame: NSRect(x: 285, y: 103, width: 85, height: 22))
        customSizeField.placeholderString = "e.g., 1920"
        customSizeField.font = .systemFont(ofSize: 12)
        customSizeField.isHidden = true
        accessoryView.addSubview(customSizeField)
        
        // MARK: Preserve Metadata Checkbox
        let metadataCheckbox = NSButton(checkboxWithTitle: "Preserve Metadata", target: nil, action: nil)
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
        
        let qualityLabel = NSTextField(labelWithString: "Compression:")
        qualityLabel.frame = NSRect(x: 0, y: 7, width: 100, height: 20)
        qualityLabel.font = .systemFont(ofSize: 12, weight: .medium)
        qualityRow.addSubview(qualityLabel)
        
        let qualitySlider = NSSlider(frame: NSRect(x: 120, y: 12, width: 200, height: 20))
        qualitySlider.minValue = 0.0
        qualitySlider.maxValue = 1.0
        qualitySlider.doubleValue = 0.85
        accessoryView.addSubview(qualitySlider)
        
        let qualityValueLabel = NSTextField(labelWithString: "85%")
        qualityValueLabel.frame = NSRect(x: 325, y: 7, width: 55, height: 20)
        qualityValueLabel.font = .systemFont(ofSize: 12)
        qualityValueLabel.alignment = .left
        accessoryView.addSubview(qualityValueLabel)
        
        // Update quality label and hide/show compression row based on format
        let updateQualityLabel = {
            let value = Int(qualitySlider.doubleValue * 100)
            qualityValueLabel.stringValue = "\(value)%"
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
        alert.addButton(withTitle: "OK")
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
