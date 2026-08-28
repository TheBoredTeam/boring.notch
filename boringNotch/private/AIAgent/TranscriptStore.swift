//
//  TranscriptStore.swift
//  boringNotch
//
//  Reads Claude Code session transcripts from ~/.claude/projects/. Each
//  session is a JSONL file; user/assistant messages, the AI-generated
//  title, and the model are extracted from it. This is the source of truth
//  for the sessions list and the chat view.
//
//  Performance: transcripts can grow to hundreds of megabytes, and the
//  sessions list refreshes every few seconds. Files are only re-read when
//  their size/mtime changed, and each read is bounded to head/tail chunks
//  (metadata lives at the start, the latest prompt/reply at the end) —
//  never the whole file. Chat messages are parsed incrementally from the
//  byte offset of the previous read.
//

import Foundation

enum TranscriptStore {
    struct Summary {
        let id: String
        var directory: String
        var title: String?
        var model: String?
        var lastPrompt: String?
        var lastReply: String?
        var updatedAt: Date
    }

    /// Per-file read caps for the scan pass.
    private static let headBytes = 65_536
    private static let tailBytes = 262_144

    private static let cacheLock = NSLock()
    /// path → (mtime, size, summary); a nil summary marks a session with no
    /// conversation so empty files aren't re-read on every scan.
    private static var summaryCache: [String: (mtime: Date, size: Int64, summary: Summary?)] = [:]
    /// path → (mtime, size, bytes already parsed, messages) for the chat view.
    private static var messageCache: [String: (mtime: Date, size: Int64, consumed: Int64, messages: [AgentChatMessage])] = [:]

    static var projectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Encodes a working directory the way Claude Code names project folders
    /// ("/Users/gio/dev" → "-Users-gio-dev").
    static func projectFolderName(for directory: String) -> String {
        directory.hasPrefix("/")
            ? directory.replacingOccurrences(of: "/", with: "-")
            : "-" + directory.replacingOccurrences(of: "/", with: "-")
    }

    // MARK: Scanning

    /// Scans all project transcripts, most recently updated first. Cached
    /// summaries are reused for files that haven't changed.
    static func scan(limit: Int = 40) -> [Summary] {
        let files = listTranscriptFiles()

        var summaries: [Summary] = []
        for (url, modified) in files.prefix(limit) {
            if let summary = summarizeIfChanged(file: url, modified: modified) {
                summaries.append(summary)
            }
        }

        // Keep the cache bounded to the scanned set.
        cacheLock.lock()
        let keep = Set(files.prefix(limit).map { $0.url.path })
        summaryCache = summaryCache.filter { keep.contains($0.key) }
        cacheLock.unlock()

        return summaries
    }

    private static func listTranscriptFiles() -> [(url: URL, modified: Date)] {
        let fm = FileManager.default
        let dirKeys: [URLResourceKey] = [.contentModificationDateKey]
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsRoot, includingPropertiesForKeys: dirKeys,
            options: [.skipsHiddenFiles]) else { return [] }

        var files: [(url: URL, modified: Date)] = []
        for dir in projectDirs where dir.hasDirectoryPath {
            guard let sessionFiles = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: dirKeys,
                options: [.skipsHiddenFiles]) else { continue }
            for file in sessionFiles where file.pathExtension == "jsonl" {
                let modKeys: Set<URLResourceKey> = [.contentModificationDateKey]
                let modified = (try? file.resourceValues(forKeys: modKeys))?
                    .contentModificationDate ?? Date.distantPast
                files.append((file, modified))
            }
        }

        files.sort { $0.modified > $1.modified }
        return files
    }

    static func fileStat(_ url: URL) -> (mtime: Date, size: Int64) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let values = try? url.resourceValues(forKeys: keys)
        return (values?.contentModificationDate ?? .distantPast,
                Int64(values?.fileSize ?? 0))
    }

    private static func summarizeIfChanged(file url: URL, modified: Date) -> Summary? {
        let stat = fileStat(url)
        cacheLock.lock()
        let cached = summaryCache[url.path]
        cacheLock.unlock()
        if let cached, cached.mtime == stat.mtime, cached.size == stat.size {
            return cached.summary
        }
        let summary = summarize(file: url, modified: modified, size: stat.size)
        cacheLock.lock()
        summaryCache[url.path] = (stat.mtime, stat.size, summary)
        cacheLock.unlock()
        return summary
    }

    /// Extracts session metadata from the head and tail of a transcript with
    /// a light-weight pass: only lines mentioning interesting keys are
    /// JSON-decoded.
    private static func summarize(file url: URL, modified: Date, size: Int64) -> Summary? {
        let id = url.deletingPathExtension().lastPathComponent
        guard let (head, tail) = readHeadAndTail(url: url, size: size) else { return nil }
        let text = head == tail ? head : head + "\n" + tail

        var directory = ""
        var title: String?
        var model: String?
        var lastPrompt: String?
        var lastReply: String?

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let l = line[...]
            if title == nil, l.contains("\"ai-title\""), let obj = decode(l) {
                title = obj["aiTitle"]?.string
                continue
            }
            if l.contains("\"cwd\""), directory.isEmpty, let obj = decode(l) {
                directory = obj["cwd"]?.string ?? ""
            }
            if l.contains("\"type\":\"user\""), let obj = decode(l) {
                if let prompt = userText(from: obj), !prompt.isEmpty {
                    lastPrompt = prompt
                }
                continue
            }
            if l.contains("\"type\":\"assistant\""), let obj = decode(l) {
                if let m = obj["message"]?["model"]?.string { model = m }
                if let reply = assistantText(from: obj), !reply.isEmpty {
                    lastReply = reply
                }
            }
        }

        // Skip sessions that contain no conversation at all.
        guard lastPrompt != nil || lastReply != nil else { return nil }

        return Summary(
            id: id,
            directory: directory,
            title: title,
            model: model,
            lastPrompt: lastPrompt,
            lastReply: lastReply,
            updatedAt: modified)
    }

    /// Reads at most the first `headBytes` and last `tailBytes` of a file so
    /// huge transcripts never hit memory whole. Small files come back with
    /// both halves equal to the full content.
    static func readHeadAndTail(url: URL, size: Int64) -> (head: String, tail: String)? {
        guard size > 0 else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        if size <= Int64(headBytes + tailBytes) {
            guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
            let text = String(decoding: data, as: UTF8.self)
            return (text, text)
        }
        guard let headData = try? handle.read(upToCount: headBytes) else { return nil }
        try? handle.seek(toOffset: UInt64(size) - UInt64(tailBytes))
        guard let tailData = try? handle.readToEnd() else { return nil }
        return (String(decoding: headData, as: UTF8.self),
                String(decoding: tailData, as: UTF8.self))
    }

    // MARK: Messages

    /// Transcript parse for the chat view, oldest first. Incremental: only
    /// the bytes added since the previous read are parsed; the result is
    /// cached per file. JSONL transcripts are append-only, so an offset just
    /// past the last complete line is where the next read resumes.
    static func messages(sessionID: String, directory: String?) -> [AgentChatMessage] {
        guard let url = transcriptURL(for: sessionID, directory: directory) else { return [] }
        let stat = fileStat(url)

        cacheLock.lock()
        let cached = messageCache[url.path]
        cacheLock.unlock()

        var messages: [AgentChatMessage]
        let consumed: Int64
        if let c = cached, c.consumed > 0, c.consumed <= stat.size {
            messages = c.messages
            consumed = parseTranscript(url: url, from: c.consumed, appendingTo: &messages)
        } else {
            messages = []
            consumed = parseTranscript(url: url, from: 0, appendingTo: &messages)
        }

        cacheLock.lock()
        messageCache[url.path] = (stat.mtime, stat.size, consumed, messages)
        if messageCache.count > 8 {
            let oldest = messageCache
                .filter { $0.key != url.path }
                .min { $0.value.mtime < $1.value.mtime }
            if let oldest { messageCache.removeValue(forKey: oldest.key) }
        }
        cacheLock.unlock()

        return messages
    }

    /// Parses complete JSONL lines starting at `offset`, appending chat
    /// messages. Returns the offset just past the last complete line so a
    /// partially written trailing line is picked up on the next read.
    private static func parseTranscript(
        url: URL, from offset: Int64, appendingTo messages: inout [AgentChatMessage]
    ) -> Int64 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }
        if offset > 0 {
            try? handle.seek(toOffset: UInt64(offset))
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return offset }
        let text = String(decoding: data, as: UTF8.self)
        guard let lastNewline = text.lastIndex(of: "\n") else { return offset }
        let complete = text[text.startIndex...lastNewline]

        for line in complete.split(separator: "\n", omittingEmptySubsequences: true) {
            let l = line[...]
            if l.contains("\"type\":\"user\""), let obj = decode(l) {
                if let prompt = userText(from: obj), !prompt.isEmpty {
                    messages.append(AgentChatMessage(id: obj["uuid"]?.string ?? UUID().uuidString,
                                                     role: .user, text: prompt))
                }
            } else if l.contains("\"type\":\"assistant\""), let obj = decode(l) {
                if let reply = assistantText(from: obj), !reply.isEmpty {
                    messages.append(AgentChatMessage(id: obj["uuid"]?.string ?? UUID().uuidString,
                                                     role: .assistant, text: reply))
                }
            }
        }
        return offset + Int64(complete.utf8.count)
    }

    /// Current session model, from the most recent assistant entry (tail
    /// chunk only).
    static func currentModel(sessionID: String, directory: String?) -> String? {
        guard let url = transcriptURL(for: sessionID, directory: directory) else { return nil }
        let stat = fileStat(url)
        guard let (_, tail) = readHeadAndTail(url: url, size: stat.size) else { return nil }
        for line in tail.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains("\"type\":\"assistant\""), let obj = decode(line[...]),
                  let model = obj["message"]?["model"]?.string else { continue }
            return model
        }
        return nil
    }

    static func transcriptURL(for sessionID: String, directory: String?) -> URL? {
        let fm = FileManager.default
        if let directory, !directory.isEmpty {
            let candidate = projectsRoot
                .appendingPathComponent(projectFolderName(for: directory))
                .appendingPathComponent("\(sessionID).jsonl")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        // Search all project folders for the session file.
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        for dir in projectDirs {
            let candidate = dir.appendingPathComponent("\(sessionID).jsonl")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    // MARK: Line parsing

    private static func decode<S: StringProtocol>(_ line: S) -> AgentJSON? {
        guard let data = String(line).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AgentJSON.self, from: data)
    }

    /// Extracts the displayable text of a user entry. Tool results and
    /// command metadata are not shown as chat bubbles.
    private static func userText(from entry: AgentJSON) -> String? {
        guard entry["isSidechain"]?.bool != true,
              entry["isMeta"]?.bool != true else { return nil }
        guard let content = entry["message"]?["content"] else { return nil }
        if let text = content.string {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            // Skip local command echoes like <command-name>/model</command-name>
            if trimmed.hasPrefix("<command-name>") || trimmed.hasPrefix("<local-command") {
                return nil
            }
            return stripSystemReminder(trimmed)
        }
        guard let blocks = content.array else { return nil }
        let texts = blocks
            .filter { $0["type"]?.string == "text" }
            .compactMap { $0["text"]?.string }
            .joined(separator: "\n\n")
        let trimmed = texts.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : stripSystemReminder(trimmed)
    }

    /// Extracts the assistant's visible text (ignoring thinking and tool
    /// use blocks).
    private static func assistantText(from entry: AgentJSON) -> String? {
        guard let blocks = entry["message"]?["content"]?.array else { return nil }
        let texts = blocks
            .filter { $0["type"]?.string == "text" }
            .compactMap { $0["text"]?.string }
            .joined(separator: "\n\n")
        let trimmed = texts.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stripSystemReminder(_ text: String) -> String {
        guard let range = text.range(of: "<system-reminder>") else { return text }
        return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}