import Foundation
import Defaults
import AppKit

@MainActor
class ClipboardStateViewModel: ObservableObject {
    static let shared = ClipboardStateViewModel()
    
    @Published var items: [ClipboardItem] = []
    
    private init() {
        items = ClipboardPersistenceService.shared.load()
    }
    
    func add(_ item: ClipboardItem) {
        // Check if the item already exists in the list
        if let existingIndex = items.firstIndex(where: { existingItem in
            switch (existingItem.kind, item.kind) {
            case (.text(let existingText), .text(let newText)):
                return existingText == newText
            }
        }) {
            // If the item already exists, do nothing (don't move it)
            return
        }
        
        // Deduplicate consecutive identical items
        if let lastItem = items.first,
           case .text(let lastText) = lastItem.kind,
           case .text(let newText) = item.kind,
           lastText == newText {
            return
        }
        
        items.insert(item, at: 0)
        trimToMaxItems()
        save()
    }
    
    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        save()
    }
    
    func togglePin(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isPinned.toggle()
            save()
        }
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.kind {
        case .text(let content):
            pasteboard.setString(content, forType: .string)
        }
    }
    
    func sortedItems() -> [ClipboardItem] {
        let pinned = items.filter { $0.isPinned }
        let unpinned = items.filter { !$0.isPinned }
        
        let sortNewestFirst = Defaults[.clipboardSortNewestFirst]
        let sortedUnpinned = sortNewestFirst
            ? unpinned.sorted { $0.timestamp > $1.timestamp }
            : unpinned.sorted { $0.timestamp < $1.timestamp }
        
        return pinned + sortedUnpinned
    }
    
    func groupedByApp() -> [(app: String, items: [ClipboardItem])] {
        let sorted = sortedItems()
        let grouped = Dictionary(grouping: sorted) { $0.sourceAppName }
        
        let sortNewestFirst = Defaults[.clipboardSortNewestFirst]
        return grouped.map { (app: $0.key, items: $0.value) }
            .sorted { first, second in
                guard let firstDate = first.items.first?.timestamp,
                      let secondDate = second.items.first?.timestamp else {
                    return false
                }
                return sortNewestFirst ? firstDate > secondDate : firstDate < secondDate
            }
    }
    
    func trimToMaxItems() {
        let pinned = items.filter { $0.isPinned }
        let unpinned = items.filter { !$0.isPinned }
        
        let maxItems = Defaults[.clipboardMaxItems]
        if unpinned.count > maxItems {
            items = pinned + Array(unpinned.prefix(maxItems))
        }
    }
    
    func clearAll() {
        items.removeAll()
        save()
    }
    
    private func save() {
        ClipboardPersistenceService.shared.save(items)
    }
}

extension ClipboardStateViewModel: ClipboardCaptureDelegate {
    func didCaptureClipboardItem(_ item: ClipboardItem) {
        add(item)
    }
}
