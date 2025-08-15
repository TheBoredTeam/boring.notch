import Foundation
import AppKit

class ClipboardManager {
    static let shared = ClipboardManager()
    
    private let pasteboard = NSPasteboard.general
    private var changeCount: Int
    private var history: [ClipboardItem] = []
    
    private init() {
        changeCount = pasteboard.changeCount
    }
    
    // MARK: - Public API
    
    func getHistory() -> [ClipboardItem] {
        cleanupOldItems()
        return history
    }
    
    func deleteItem(_ item: ClipboardItem) {
        history.removeAll { $0.id == item.id }
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        pasteboard.clearContents()
        
        switch item.content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .image(let image):
            pasteboard.writeObjects([image])
        }
        
        // Also mark as most recent in history
        history.removeAll { $0.id == item.id }
        history.insert(item, at: 0)
    }
    
    // Start monitoring for new clipboard content
    func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.checkForNewContent()
        }
    }
    
    // MARK: - Private Helpers
    
    private func checkForNewContent() {
        if pasteboard.changeCount != changeCount {
            changeCount = pasteboard.changeCount
            if let newItem = readClipboard() {
                // Avoid duplicates in a row
                if history.first?.content != newItem.content {
                    history.insert(newItem, at: 0)
                }
                cleanupOldItems()
            }
        }
    }
    
    private func readClipboard() -> ClipboardItem? {
        if let string = pasteboard.string(forType: .string) {
            return ClipboardItem(content: .text(string))
        }
        
        if let image = NSImage(pasteboard: pasteboard) {
            return ClipboardItem(content: .image(image))
        }
        
        return nil
    }
    
    private func cleanupOldItems() {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago
        history.removeAll { $0.dateAdded < cutoff }
    }
}
