import Foundation

struct DailyConclusionPreferences: Codable, Equatable {
    var isEnabled = false
    static var defaultDirectory: URL {
        FileManager.default.homeDirectory(forUser: NSUserName())!
            .appendingPathComponent("Documents/Boring Notch Diary", isDirectory: true)
    }

    var directoryPath = Self.defaultDirectory.path
    var directoryBookmark: Data?
}

/// Writes a new entry exclusively: existing journals are never replaced.
struct DailyConclusionStore {
    func save(text: String, date: Date, directory: URL, calendar: Calendar = .current) throws -> URL? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
        let data = Data(text.utf8)
        // The chosen directory must still exist. Do not silently recreate a moved folder.
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw CocoaError(.fileWriteInvalidFileName) }
        for index in 1...10_000 {
            let suffix = index == 1 ? "" : "-\(index)"
            let url = directory.appendingPathComponent("\(day)\(suffix).md")
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
