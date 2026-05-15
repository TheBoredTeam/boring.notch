import Foundation

/// Persistent long-term facts about the user. Loaded from
/// `~/Library/Application Support/Kairo/long_term_memory.json` on init;
/// rewritten after every `add(_:)`. Seeded with a baseline set of facts
/// the first time the file doesn't exist.
final class KairoLongTermMemory {
    private(set) var facts: [String]

    private let storeURL: URL
    private let seed: [String] = [
        "John builds KushTunes, Ember Records, Tech4SSD.",
        "Manages socials for Lady Kola.",
        "Mac username: wizlox.",
        "Based in Kampala."
    ]

    init(storeURL: URL? = nil) {
        let url = storeURL ?? Self.defaultStoreURL()
        self.storeURL = url

        if let loaded = Self.load(from: url) {
            self.facts = loaded
        } else {
            self.facts = seed
            Self.save(seed, to: url)
        }
    }

    func add(_ fact: String) {
        let trimmed = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !facts.contains(trimmed) else { return }
        facts.append(trimmed)
        Self.save(facts, to: storeURL)
    }

    func all() -> [String] { facts }

    // MARK: - Persistence

    private static func defaultStoreURL() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask,
                                      appropriateFor: nil,
                                      create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("Kairo", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("long_term_memory.json")
    }

    private static func load(from url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url),
              let facts = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return facts
    }

    private static func save(_ facts: [String], to url: URL) {
        guard let data = try? JSONEncoder().encode(facts) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
