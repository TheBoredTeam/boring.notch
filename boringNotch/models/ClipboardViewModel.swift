import SwiftUI
import Combine
import AppKit

class ClipboardViewModel: ObservableObject {
    // Published list of clipboard items for the UI
    @Published var items: [ClipboardItem] = []
    
    // Track which item is currently the "active" clipboard entry
    @Published var activeItemID: UUID?
    
    private var timer: AnyCancellable?
    
    init() {
        // Initial load
        items = ClipboardManager.shared.getHistory()
        
        // Poll for changes every second
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                let newItems = ClipboardManager.shared.getHistory()
                if newItems != self.items {
                    self.items = newItems
                }
            }
    }
    
    // Delete a specific history item
    func delete(_ item: ClipboardItem) {
        ClipboardManager.shared.deleteItem(item)
        items = ClipboardManager.shared.getHistory()
    }
    
    // Mark an item as active (highlight in UI)
    func setActiveItem(_ item: ClipboardItem) {
        activeItemID = item.id
    }
    
    // Copy back to system clipboard
    func copyToClipboard(_ item: ClipboardItem) {
        ClipboardManager.shared.copyToClipboard(item)
        setActiveItem(item)
    }
}
