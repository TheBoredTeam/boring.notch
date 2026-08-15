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
import ObjectiveC

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
    }

    func loadThumbnail() async {
        guard let url = item.fileURL else { return }
        if let image = await ThumbnailService.shared.thumbnail(for: url, size: CGSize(width: 56, height: 56)) {
            self.thumbnail = NSImage(cgImage: image, size: CGSize(width: 56, height: 56))
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
            if let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) {
                provider.registerObject(url as NSURL, visibility: .all)
            } else {
                provider.registerObject(item.displayName as NSString, visibility: .all)
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
        var urls: [URL] = []
        var textItems: [String] = []
        for item in items {
            switch item.kind {
            case .file:
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
        ShelfContextMenuBuilder.present(
            item: item, event: event, in: view,
            onShare: { [weak self] v in self?.shareItem(from: v) },
            onQuickLook: { [weak self] urls in self?.onQuickLookRequest?(urls) }
        )
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
}
