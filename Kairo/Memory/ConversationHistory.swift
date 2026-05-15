import Foundation

/// Persistent record of past user↔kairo turns across app launches.
///
/// On disk at
/// `~/Library/Application Support/Kairo/conversation_history.json` (sandboxed).
/// Stores the last `maxTurns` exchanges as `Turn` rows so the LLM can pick
/// up where the conversation left off.
///
/// This is *separate* from `KairoShortTermMemory`:
///   - ShortTermMemory: last 20 raw lines in RAM for system-prompt context.
///   - ConversationHistory: structured Turn objects, persisted, with role +
///     timestamp + (optional) tool trace.
///
/// Both are read by `ContextBuilder` so the model gets recent context
/// regardless of where it came from.
@MainActor
final class KairoConversationHistory {

    struct Turn: Codable, Hashable {
        let id: UUID
        let userInput: String
        let kairoReply: String
        let timestamp: Date
        let toolTrace: [String]    // optional THOUGHT / [CALL] / [OBSERVATION] log

        init(userInput: String, kairoReply: String, toolTrace: [String] = []) {
            self.id = UUID()
            self.userInput = userInput
            self.kairoReply = kairoReply
            self.timestamp = Date()
            self.toolTrace = toolTrace
        }
    }

    private let storeURL: URL
    private let maxTurns: Int
    private(set) var turns: [Turn] = []

    init(storeURL: URL? = nil, maxTurns: Int = 200) {
        self.maxTurns = maxTurns
        self.storeURL = storeURL ?? Self.defaultStoreURL()
        self.turns = Self.load(from: self.storeURL)
    }

    // MARK: - Public API

    /// Append a completed turn. Trims to `maxTurns` and persists.
    func append(_ turn: Turn) {
        turns.append(turn)
        if turns.count > maxTurns { turns.removeFirst(turns.count - maxTurns) }
        save()
    }

    /// Convenience that builds the Turn from raw strings.
    func record(userInput: String, kairoReply: String, toolTrace: [String] = []) {
        append(Turn(userInput: userInput, kairoReply: kairoReply, toolTrace: toolTrace))
    }

    /// Most-recent N turns, oldest → newest, formatted for the LLM context.
    /// "user: ..." / "kairo: ..." — matches `KairoShortTermMemory.recent`.
    func recent(count: Int = 5) -> [String] {
        let tail = turns.suffix(count)
        var lines: [String] = []
        for t in tail {
            lines.append("user: \(t.userInput)")
            lines.append("kairo: \(t.kairoReply)")
        }
        return lines
    }

    /// Wipe everything on disk + in memory. Used by /reset or a Privacy panel.
    func clear() {
        turns.removeAll()
        try? FileManager.default.removeItem(at: storeURL)
    }

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
        return dir.appendingPathComponent("conversation_history.json")
    }

    private static func load(from url: URL) -> [Turn] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder.iso8601.decode([Turn].self, from: data) else {
            return []
        }
        return decoded
    }

    private func save() {
        guard let data = try? JSONEncoder.iso8601.encode(turns) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

// MARK: - JSON helpers (iso8601 dates)

private extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
