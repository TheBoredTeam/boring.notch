//
//  ClipboardManager.swift
//  boringNotch
//
//  Created by boringNotch contributors on 2026-04-19.
//

import AppKit
import Combine
import Defaults
import Foundation

/// Monitors NSPasteboard for changes and maintains clipboard history
class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published var items: [ClipboardItem] = []
    @Published var searchQuery: String = ""

    private var changeCount: Int
    private var timer: Timer?
    private let pasteboard = NSPasteboard.general
    private let pollingInterval: TimeInterval = 0.5

    var filteredItems: [ClipboardItem] {
        let query = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
        let allItems: [ClipboardItem]

        if query.isEmpty {
            allItems = items
        } else {
            allItems = items.filter { item in
                switch item.type {
                case .text:
                    return item.textContent?.lowercased().contains(query) ?? false
                case .fileURL:
                    return item.fileURL?.lastPathComponent.lowercased().contains(query) ?? false
                case .image:
                    return false
                }
            }
        }

        // Pinned items first, then by timestamp
        return allItems.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.timestamp > b.timestamp
        }
    }

    private init() {
        changeCount = pasteboard.changeCount
    }

    func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) {
            [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChanges() {
        guard Defaults[.enableClipboardHistory] else { return }

        let currentCount = pasteboard.changeCount
        guard currentCount != changeCount else { return }
        changeCount = currentCount

        // Get the frontmost app that isn't us
        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleID =
            frontApp?.bundleIdentifier != Bundle.main.bundleIdentifier
            ? frontApp?.bundleIdentifier : nil

        guard let newItem = ClipboardItem.fromPasteboard(pasteboard, bundleID: bundleID) else {
            return
        }

        // Deduplicate: skip if identical to most recent non-pinned item
        if let lastItem = items.first(where: { !$0.isPinned }) {
            if lastItem.type == newItem.type {
                switch newItem.type {
                case .text:
                    if lastItem.textContent == newItem.textContent { return }
                case .fileURL:
                    if lastItem.fileURL == newItem.fileURL { return }
                case .image:
                    break  // Always add images (comparing pixel data is expensive)
                }
            }
        }

        DispatchQueue.main.async {
            self.items.insert(newItem, at: 0)

            // Trim to max history size (keep pinned items always)
            let maxItems = Defaults[.clipboardHistorySize]
            let pinned = self.items.filter { $0.isPinned }
            var unpinned = self.items.filter { !$0.isPinned }
            if unpinned.count > maxItems {
                unpinned = Array(unpinned.prefix(maxItems))
            }
            self.items = pinned + unpinned
        }
    }

    /// Pastes an item by writing to pasteboard. Does NOT simulate Cmd+V —
    /// the user must paste manually. This avoids the Teams/sandboxed app issue.
    func selectItem(_ item: ClipboardItem) {
        switch item.type {
        case .text:
            pasteboard.clearContents()
            pasteboard.setString(item.textContent ?? "", forType: .string)
        case .image:
            if let image = item.imageContent, let tiffData = image.tiffRepresentation {
                pasteboard.clearContents()
                pasteboard.setData(tiffData, forType: .tiff)
            }
        case .fileURL:
            if let url = item.fileURL {
                pasteboard.clearContents()
                pasteboard.writeObjects([url as NSURL])
            }
        }
        // Update changeCount so we don't re-capture our own paste
        changeCount = pasteboard.changeCount
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
    }

    func removeItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearHistory() {
        items.removeAll { !$0.isPinned }
    }

    deinit {
        stopMonitoring()
    }
}
