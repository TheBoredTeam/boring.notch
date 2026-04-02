import Foundation
import Defaults

@MainActor
class ClipboardPersistenceService {
    static let shared = ClipboardPersistenceService()
    
    private init() {}
    
    // Volatile data in memory
    private var items: [ClipboardItem] = []
    
    // Persistence file path
    private var persistenceURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("com.theboringteam.boringNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder.appendingPathComponent("clipboard_items.json")
    }
    
    func save(_ items: [ClipboardItem]) {
        self.items = items
        
        // Save to disk only if the option is enabled
        if Defaults[.clipboardPersistOnQuit] {
            saveToDisk(items)
        }
    }
    
    func load() -> [ClipboardItem] {
        // Load from disk only if the option is enabled
        if Defaults[.clipboardPersistOnQuit] {
            return loadFromDisk()
        }
        return items
    }
    
    func clear() {
        items.removeAll()
        clearFromDisk()
    }
    
    // MARK: - Disk persistence
    
    private func saveToDisk(_ items: [ClipboardItem]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            print("Error saving clipboard to disk: \(error)")
        }
    }
    
    private func loadFromDisk() -> [ClipboardItem] {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: persistenceURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ClipboardItem].self, from: data)
        } catch {
            print("Error loading clipboard from disk: \(error)")
            return []
        }
    }
    
    private func clearFromDisk() {
        try? FileManager.default.removeItem(at: persistenceURL)
    }
}
