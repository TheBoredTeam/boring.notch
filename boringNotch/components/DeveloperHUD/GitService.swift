//
//  GitService.swift
//  boringNotch
//
//  Reads repository state by invoking the system `git` binary off the main
//  thread. Paths are never logged.
//

import Foundation

struct GitSnapshot: Equatable {
    enum Status: Equatable { case clean, modified, untracked, unknown }

    var projectName: String
    var branch: String
    var status: Status
    var changedFiles: Int
    var untrackedFiles: Int
    var lastCommitMessage: String?
    var lastCommitDate: Date?
    var gitAvailable: Bool
}

enum GitServiceError: Error { case notARepository, accessDenied }

struct GitService {
    /// Resolves a security-scoped bookmark and returns a snapshot of that repository.
    func snapshot(forBookmark bookmark: Data) async throws -> GitSnapshot {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            throw GitServiceError.accessDenied
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try await Task.detached(priority: .utility) { try Self.read(url) }.value
    }

    private static func read(_ url: URL) throws -> GitSnapshot {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.appendingPathComponent(".git").path) else {
            throw GitServiceError.notARepository
        }
        let name = url.lastPathComponent

        // Single status call gives branch + changes.
        guard let status = run(["status", "--porcelain=v1", "--branch", "--untracked-files=normal"], in: url) else {
            // git unavailable: fall back to reading HEAD directly.
            return GitSnapshot(projectName: name, branch: headBranch(url) ?? "—", status: .unknown,
                               changedFiles: 0, untrackedFiles: 0, lastCommitMessage: nil,
                               lastCommitDate: nil, gitAvailable: false)
        }

        var branch = "—"
        var changed = 0
        var untracked = 0
        for line in status.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("## ") {
                branch = parseBranch(String(line.dropFirst(3)))
            } else if line.hasPrefix("??") {
                untracked += 1
            } else {
                changed += 1
            }
        }

        var message: String?
        var date: Date?
        if let log = run(["log", "-1", "--format=%s%x1f%ct"], in: url) {
            let parts = log.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\u{1f}")
            if parts.count == 2 {
                message = parts[0]
                if let ts = TimeInterval(parts[1]) { date = Date(timeIntervalSince1970: ts) }
            }
        }

        let state: GitSnapshot.Status = changed > 0 ? .modified : (untracked > 0 ? .untracked : .clean)
        return GitSnapshot(projectName: name, branch: branch, status: state,
                           changedFiles: changed + untracked, untrackedFiles: untracked,
                           lastCommitMessage: message, lastCommitDate: date, gitAvailable: true)
    }

    private static func parseBranch(_ raw: String) -> String {
        if raw.hasPrefix("No commits yet on ") { return String(raw.dropFirst("No commits yet on ".count)) }
        if raw.hasPrefix("HEAD (no branch)") { return "detached HEAD" }
        if let r = raw.range(of: "...") { return String(raw[..<r.lowerBound]) }
        if let r = raw.range(of: " [") { return String(raw[..<r.lowerBound]) }
        return raw
    }

    private static func headBranch(_ url: URL) -> String? {
        guard let head = try? String(contentsOf: url.appendingPathComponent(".git/HEAD"), encoding: .utf8) else { return nil }
        let t = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("ref: refs/heads/") { return String(t.dropFirst("ref: refs/heads/".count)) }
        return "detached HEAD"
    }

    /// Runs git with a hard timeout. Returns nil if git cannot be launched or fails.
    private static func run(_ args: [String], in directory: URL, timeout: TimeInterval = 5) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path, "--no-optional-locks"] + args
        process.environment = ["GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
