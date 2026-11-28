//
//  CodexActivity.swift
//  boringNotch
//

import AppKit
import Combine
import Darwin
import Foundation
import SQLite3
import SwiftUI

struct CodexActivity: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let startedAt: Date
    let updatedAt: Date
    let status: CodexTaskStatus

    @MainActor
    func openConversation() {
        guard UUID(uuidString: id) != nil,
              let url = URL(string: "codex://threads/\(id)") else { return }
        NSWorkspace.shared.open(url)
    }
}

enum CodexTaskStatus: String, Sendable {
    case running, completed, interrupted, failed, idle

    var label: String {
        switch self {
        case .running: return "Running"
        case .completed: return "Completed"
        case .interrupted: return "Interrupted"
        case .failed: return "Failed"
        case .idle: return "Idle"
        }
    }

    var color: Color {
        switch self {
        case .running: return .green
        case .completed: return .mint
        case .interrupted: return .orange
        case .failed: return .red
        case .idle: return .gray
        }
    }
}

struct CodexQuotaWindow: Equatable, Sendable {
    let remaining: Int
    let resetsAt: Date?
}

struct CodexQuota: Equatable, Sendable {
    let fiveHour: CodexQuotaWindow?
    let weekly: CodexQuotaWindow?
    let observedAt: Date
}

@MainActor
final class CodexActivityManager: ObservableObject {
    static let shared = CodexActivityManager()

    private static let folderBookmarkKey = "codexActivityFolderBookmark"
    private static let enabledKey = "codexActivityEnabled"

    @Published private(set) var quota: CodexQuota?
    private var lastQuotaRefresh = Date.distantPast
    @Published private(set) var recentActivities: [CodexActivity] = []
    @Published private(set) var activeActivities: [CodexActivity] = []
    @Published private(set) var activeActivityCount = 0
    @Published private(set) var hasFolderAccess = false
    @Published private(set) var isEnabled: Bool
    @Published private(set) var errorMessage: String?
    @Published var isShowingDetails = false

    private var codexFolderURL: URL?
    private var isAccessingSecurityScopedResource = false
    private var refreshTimer: Timer?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        if isEnabled {
            restoreFolderBookmark()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    deinit {
        refreshTimer?.invalidate()
        if isAccessingSecurityScopedResource {
            codexFolderURL?.stopAccessingSecurityScopedResource()
        }
    }

    /// Only offer the task panel when a healthy connection has real content.
    var canShowDetails: Bool {
        isEnabled && hasFolderAccess && errorMessage == nil && !recentActivities.isEmpty
    }

    var primaryActivityTitle: String {
        activeActivities.first?.title ?? "Codex"
    }

    var statusDescription: String {
        guard isEnabled else {
            return "Codex activity is turned off."
        }
        if let errorMessage {
            return errorMessage
        }
        guard hasFolderAccess else {
            return "Choose the ~/.codex folder to connect."
        }
        if activeActivityCount == 0 {
            return "Connected. No Codex tasks are running."
        }
        return activeActivityCount == 1
            ? "1 Codex task is running."
            : "\(activeActivityCount) Codex tasks are running."
    }

    var hasSavedFolder: Bool {
        UserDefaults.standard.data(forKey: Self.folderBookmarkKey) != nil
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            if !isAccessingSecurityScopedResource {
                if let codexFolderURL {
                    isAccessingSecurityScopedResource = codexFolderURL.startAccessingSecurityScopedResource()
                    hasFolderAccess = isAccessingSecurityScopedResource
                    errorMessage = isAccessingSecurityScopedResource
                        ? nil
                        : "Codex folder access expired. Choose the folder again."
                } else {
                    restoreFolderBookmark()
                }
            }
            refresh()
        } else {
            recentActivities = []
            activeActivities = []
            activeActivityCount = 0
            isShowingDetails = false
            if isAccessingSecurityScopedResource {
                codexFolderURL?.stopAccessingSecurityScopedResource()
                isAccessingSecurityScopedResource = false
            }
            hasFolderAccess = false
        }
    }

    func forgetCodexFolder() {
        isShowingDetails = false
        if isAccessingSecurityScopedResource {
            codexFolderURL?.stopAccessingSecurityScopedResource()
        }
        codexFolderURL = nil
        quota = nil
        lastQuotaRefresh = .distantPast
        isAccessingSecurityScopedResource = false
        hasFolderAccess = false
        isShowingDetails = false
        recentActivities = []
        activeActivities = []
        activeActivityCount = 0
        errorMessage = nil
        UserDefaults.standard.removeObject(forKey: Self.folderBookmarkKey)
    }

    func chooseCodexFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose the Codex data folder"
        panel.message = "Select ~/.codex. Boring Notch will read active task status and titles only."
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        // The sandbox's homeDirectoryForCurrentUser points to the app container.
        // Let the system picker navigate to the login user's actual Codex folder.
        if let user = getpwuid(getuid()), let homePath = user.pointee.pw_dir {
            panel.directoryURL = URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
                .appendingPathComponent(".codex", isDirectory: true)
        }

        guard panel.runModal() == .OK, let selectedFolder = panel.url else { return }
        guard selectedFolder.startAccessingSecurityScopedResource() else {
            errorMessage = "Boring Notch could not access that folder. Please choose it again."
            return
        }
        defer { selectedFolder.stopAccessingSecurityScopedResource() }
        guard CodexActivityScanner.containsCodexDatabases(in: selectedFolder) else {
            errorMessage = "That folder does not contain Codex activity databases."
            return
        }

        do {
            let bookmark = try selectedFolder.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var isStale = false
            let readOnlyFolderURL = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard readOnlyFolderURL.startAccessingSecurityScopedResource() else {
                errorMessage = "Boring Notch could not access that folder. Please choose it again."
                return
            }
            if isAccessingSecurityScopedResource {
                codexFolderURL?.stopAccessingSecurityScopedResource()
            }
            codexFolderURL = readOnlyFolderURL
            quota = nil
            lastQuotaRefresh = .distantPast
            isAccessingSecurityScopedResource = isEnabled
            hasFolderAccess = isEnabled
            errorMessage = nil
            UserDefaults.standard.set(bookmark, forKey: Self.folderBookmarkKey)
            if !isEnabled {
                readOnlyFolderURL.stopAccessingSecurityScopedResource()
            }
            refresh()
        } catch {
            errorMessage = "Boring Notch could not save access to that folder."
        }
    }

    func refresh() {
        guard isEnabled, let codexFolderURL, isAccessingSecurityScopedResource else {
            recentActivities = []
            activeActivities = []
            activeActivityCount = 0
            isShowingDetails = false
            return
        }

        if Date().timeIntervalSince(lastQuotaRefresh) >= 30 {
            lastQuotaRefresh = Date()
            Task { [weak self] in
                let value = await Task.detached(priority: .utility) {
                    CodexActivityScanner.readQuota(in: codexFolderURL)
                }.value
                guard let self, self.isEnabled, self.codexFolderURL == codexFolderURL else { return }
                self.quota = value
            }
        }
        let snapshot = CodexActivityScanner.scan(in: codexFolderURL)
        recentActivities = snapshot.activities
        activeActivities = snapshot.activities.filter { $0.status == .running }
        activeActivityCount = snapshot.totalCount
        errorMessage = snapshot.errorMessage
        if !canShowDetails { isShowingDetails = false }
    }

    private func restoreFolderBookmark() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.folderBookmarkKey) else { return }

        do {
            var isStale = false
            let folderURL = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard folderURL.startAccessingSecurityScopedResource() else {
                errorMessage = "Codex folder access expired. Choose the folder again."
                return
            }
            codexFolderURL = folderURL
            isAccessingSecurityScopedResource = true
            hasFolderAccess = true

            if isStale {
                let refreshedBookmark = try folderURL.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(refreshedBookmark, forKey: Self.folderBookmarkKey)
            }
        } catch {
            errorMessage = "Codex folder access expired. Choose the folder again."
        }
    }
}

struct CodexActivitySnapshot {
    let activities: [CodexActivity]
    let totalCount: Int
    let errorMessage: String?
}

/// Reads task status from local SQLite indexes and usage metadata from session files.
/// SQLite connections are read-only; session message text is not retained or displayed.
@MainActor
enum CodexActivityScanner {
    nonisolated static func readQuota(in folder: URL) -> CodexQuota? {
        guard let files = FileManager.default.enumerator(
            at: folder.appendingPathComponent("sessions"),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let urls = files.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .sorted { modified($0) > modified($1) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var latest: CodexQuota?
        for url in urls.prefix(20) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            guard let length = try? handle.seekToEnd() else { continue }
            try? handle.seek(toOffset: length > 524_288 ? length - 524_288 : 0)
            guard let data = try? handle.readToEnd() else { continue }
            let contents = String(decoding: data, as: UTF8.self)
            for line in contents.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
                guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                      object["type"] as? String == "event_msg",
                      let payload = object["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let limits = payload["rate_limits"] as? [String: Any],
                      let timestamp = object["timestamp"] as? String,
                      let date = formatter.date(from: timestamp),
                      (limits["limit_id"] as? String ?? "codex") == "codex" else { continue }
                func window(_ minutes: Int) -> CodexQuotaWindow? {
                    for key in ["primary", "secondary"] {
                        guard let value = limits[key] as? [String: Any],
                              value["window_minutes"] as? Int == minutes,
                              let used = value["used_percent"] as? Double else { continue }
                        let reset = (value["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                        if let reset, reset <= Date() { return nil }
                        return CodexQuotaWindow(
                            remaining: max(0, min(100, Int((100 - used).rounded()))), resetsAt: reset
                        )
                    }
                    return nil
                }
                let five = window(300)
                let week = window(10_080)
                if (five != nil || week != nil), latest.map({ date > $0.observedAt }) ?? true {
                    latest = CodexQuota(fiveHour: five, weekly: week, observedAt: date)
                }
                break
            }
        }
        return latest
    }

    private static let maximumActivityAge: TimeInterval = 24 * 60 * 60
    private static let maximumDisplayedActivities = 12
    private static var sessionMap: [String: String] = [:]
    private static var lastSessionMapRefresh = Date.distantPast
    private static var lastSessionMapFolder: URL?

    private static var defaultTitleIndexURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexNotch", isDirectory: true)
            .appendingPathComponent("task-titles.json")
    }

    static func containsCodexDatabases(in folder: URL) -> Bool {
        !databaseFiles(in: folder, prefix: "state_").isEmpty
            && !databaseFiles(in: folder, prefix: "thread_history_").isEmpty
    }

    static func scan(in folder: URL, titleIndexURL: URL? = nil) -> CodexActivitySnapshot {
        let titleIndexURL = titleIndexURL ?? defaultTitleIndexURL
        let stateFiles = databaseFiles(in: folder, prefix: "state_")
        let historyFiles = databaseFiles(in: folder, prefix: "thread_history_")
        guard !stateFiles.isEmpty, !historyFiles.isEmpty else {
            return CodexActivitySnapshot(activities: [], totalCount: 0,
                errorMessage: "Codex activity databases were not found. Select ~/.codex.")
        }
        refreshSessionMap(in: folder)
        let cutoff = Int64(Date().timeIntervalSince1970 - maximumActivityAge)
        var turns: [String: (status: CodexTaskStatus, started: Date, updated: Date)] = [:]
        var succeeded = false
        for file in historyFiles {
            let rows = withDatabase(at: file) { database -> [(String, String, Int64, Int64)]? in
                let sql = """
                SELECT thread_id, status, started_at, COALESCE(completed_at, started_at)
                FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY thread_id ORDER BY started_at DESC, rollout_ordinal DESC) AS position
                      FROM thread_turns WHERE started_at >= ?) WHERE position = 1
                """
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                      let statement else { return nil }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_int64(statement, 1, cutoff)
                var rows: [(String, String, Int64, Int64)] = []
                var result = sqlite3_step(statement)
                while result == SQLITE_ROW {
                    if let id = stringValue(statement, column: 0), let status = stringValue(statement, column: 1) {
                        rows.append((id, status, sqlite3_column_int64(statement, 2), sqlite3_column_int64(statement, 3)))
                    }
                    result = sqlite3_step(statement)
                }
                return result == SQLITE_DONE ? rows : nil
            }
            guard let rows = rows ?? nil else { continue }
            succeeded = true
            for (runtimeID, rawStatus, started, updated) in rows {
                let id = sessionMap[runtimeID] ?? runtimeID
                let status: CodexTaskStatus
                switch rawStatus {
                case "inProgress": status = .running
                case "completed": status = .completed
                case "interrupted": status = .interrupted
                case "failed": status = .failed
                default: status = .idle
                }
                let start = Date(timeIntervalSince1970: TimeInterval(started))
                let update = Date(timeIntervalSince1970: TimeInterval(updated))
                if let previous = turns[id] {
                    if previous.status == .running && status != .running { continue }
                    if previous.status == status && previous.started >= start { continue }
                    if status != .running && previous.updated >= update { continue }
                }
                turns[id] = (status, start, update)
            }
        }
        guard succeeded else {
            return CodexActivitySnapshot(activities: [], totalCount: 0,
                errorMessage: "Could not read Codex activity status. Choose ~/.codex again.")
        }
        var titleIndex = (try? Data(contentsOf: titleIndexURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        let oldIndex = titleIndex
        var recent: [String: Date] = [:]
        var excludedIDs = Set<String>()
        for file in stateFiles {
            withDatabase(at: file) { database in
                let sql = "SELECT id, COALESCE(NULLIF(name, ''), title), updated_at, archived, source FROM threads ORDER BY updated_at DESC LIMIT 1000"
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                      let statement else { return }
                defer { sqlite3_finalize(statement) }
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let id = stringValue(statement, column: 0) else { continue }
                    if sqlite3_column_int(statement, 3) != 0 || (stringValue(statement, column: 4)?.contains("\"subagent\"") ?? false) {
                        excludedIDs.insert(id)
                        continue
                    }
                    if let name = stringValue(statement, column: 1)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
                        titleIndex[id] = name
                    }
                    recent[id] = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 2)))
                }
            }
        }
        if titleIndex != oldIndex, let data = try? JSONEncoder().encode(titleIndex) {
            try? FileManager.default.createDirectory(at: titleIndexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: titleIndexURL, options: .atomic)
        }
        // Keep running conversations plus the most recently updated conversations.
        let recentIDs = recent.sorted { $0.value > $1.value }.prefix(maximumDisplayedActivities).map(\.key)
        let ids = Set(recentIDs).union(turns.keys).subtracting(excludedIDs)
        let activities = ids.map { id -> CodexActivity in
            let turn = turns[id]
            let updated = turn?.updated ?? recent[id] ?? .distantPast
            return CodexActivity(id: id, title: titleIndex[id] ?? "Codex task",
                startedAt: turn?.started ?? updated, updatedAt: updated, status: turn?.status ?? .idle)
        }.sorted {
            if ($0.status == .running) != ($1.status == .running) { return $0.status == .running }
            return $0.updatedAt > $1.updatedAt
        }
        return CodexActivitySnapshot(activities: Array(activities.prefix(maximumDisplayedActivities)),
            totalCount: activities.filter { $0.status == .running }.count, errorMessage: nil)
    }

    private static func refreshSessionMap(in folder: URL) {
        guard folder != lastSessionMapFolder || Date().timeIntervalSince(lastSessionMapRefresh) > 10 else { return }
        if folder != lastSessionMapFolder { sessionMap = [:] }
        lastSessionMapFolder = folder
        lastSessionMapRefresh = Date()
        for directory in ["sessions", "archived_sessions"] {
            guard let files = FileManager.default.enumerator(at: folder.appendingPathComponent(directory),
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let file as URL in files where file.pathExtension == "jsonl" {
                // Rollout filenames contain conversationID_runtimeSessionID. Read filenames only.
                let parts = file.deletingPathExtension().lastPathComponent.split(separator: "_")
                guard parts.count == 2 else { continue }
                let conversationID = String(parts[0].suffix(36))
                let runtimeID = String(parts[1])
                if UUID(uuidString: conversationID) != nil, UUID(uuidString: runtimeID) != nil {
                    sessionMap[runtimeID] = conversationID
                }
            }
        }
    }

    private static func databaseFiles(in folder: URL, prefix: String) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]))?.filter {
                $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "sqlite"
            } ?? []
    }

    private static func withDatabase<T>(at file: URL, read: (OpaquePointer) -> T) -> T? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)
        return read(database)
    }

    private static func stringValue(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: UnsafeRawPointer(value).assumingMemoryBound(to: CChar.self))
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

struct CodexLiveActivityView: View {
    @EnvironmentObject private var viewModel: BoringViewModel
    @ObservedObject private var manager = CodexActivityManager.shared

    var body: some View {
        Button {
            manager.activeActivities.first?.openConversation()
        } label: {
            GeometryReader { geometry in
                let gap = min(viewModel.closedNotchSize.width, geometry.size.width * 0.45)
                let side = max(0, (geometry.size.width - gap - 24) / 2)
                HStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(manager.primaryActivityTitle)
                                .font(.headline).foregroundStyle(.white)
                                .lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(manager.activeActivityCount == 1 ? "Codex is working" : "\(manager.activeActivityCount) tasks running")
                                .font(.subheadline).foregroundStyle(.gray).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                    }
                    .frame(width: side, alignment: .leading)
                    .clipped()
                    Color.clear.frame(width: gap)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(manager.quota?.fiveHour.map { "5h \($0.remaining)% left" } ?? "5h —")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        if let reset = manager.quota?.fiveHour?.resetsAt {
                            Text("Resets \(reset.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2).foregroundStyle(.gray)
                        } else {
                            Text("Reset unavailable").font(.caption2).foregroundStyle(.gray)
                        }
                    }
                    .lineLimit(1)
                    .frame(width: side, alignment: .trailing)
                    .clipped()
                }
                .padding(.horizontal, 12)
                .frame(height: geometry.size.height)
            }
            .frame(height: max(38, viewModel.effectiveClosedNotchHeight))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open this conversation in Codex")
    }
}

struct CodexActivityDetailsView: View {
    @ObservedObject private var manager = CodexActivityManager.shared

    var body: some View {
        CodexActivityDetailsContent(activities: manager.recentActivities,
            activeCount: manager.activeActivityCount, statusDescription: manager.statusDescription, quota: manager.quota) {
                manager.isShowingDetails = false
            }
    }
}

struct CodexActivityDetailsContent: View {
    let activities: [CodexActivity]
    let activeCount: Int
    let statusDescription: String
    var quota: CodexQuota? = nil
    let showHome: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Codex conversations", systemImage: "terminal.fill")
                    .font(.headline).foregroundStyle(.white)
                Text("\(activeCount) Running")
                    .font(.caption).foregroundStyle(.green)
                Spacer()
                Button {
                    showHome()
                } label: {
                    Label("Music & Calendar", systemImage: "music.note")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            if let quota {
                HStack(spacing: 16) {
                    quotaLabel("5h", quota.fiveHour)
                    quotaLabel("Week", quota.weekly)
                    Spacer()
                    Text("Updated \(quota.observedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("Usage unavailable").font(.caption).foregroundStyle(.secondary)
            }
            if activities.isEmpty {
                Text(statusDescription).font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(activities) { activity in
                            HStack(spacing: 10) {
                                if activity.status == .running {
                                    ProgressView().controlSize(.small).tint(.green)
                                        .frame(width: 18)
                                } else {
                                    Image(systemName: activity.status == .failed ? "exclamationmark.circle.fill" : "circle.fill")
                                        .font(.system(size: 9)).foregroundStyle(activity.status.color)
                                        .frame(width: 18)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Button {
                                        activity.openConversation()
                                    } label: {
                                        Text(activity.title).font(.subheadline.weight(.medium))
                                            .foregroundStyle(.white).lineLimit(1)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Open this conversation in Codex")
                                    Text("\(activity.status.label) · \(Self.elapsedTime(since: activity.status == .running ? activity.startedAt : activity.updatedAt))")
                                        .font(.caption).foregroundStyle(activity.status.color)
                                }
                                Spacer(minLength: 8)
                            }
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                            if activity.id != activities.last?.id {
                                Divider().overlay(.white.opacity(0.1))
                            }
                        }
                    }
                }
                .frame(maxHeight: 210)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }

    private func quotaLabel(_ title: String, _ quota: CodexQuotaWindow?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title): \(quota.map { "\($0.remaining)% left" } ?? "Unavailable")").font(.caption.weight(.semibold)).foregroundStyle(.white)
            if let reset = quota?.resetsAt { Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private static func elapsedTime(since start: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }
}

struct CodexActivitySettingsView: View {
    @ObservedObject private var manager = CodexActivityManager.shared

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Show Codex activity in the notch",
                    isOn: Binding(
                        get: { manager.isEnabled },
                        set: { manager.setEnabled($0) }
                    )
                )

                Button(manager.hasSavedFolder ? "Change Codex data folder…" : "Choose ~/.codex folder…") {
                    manager.chooseCodexFolder()
                }

                if manager.hasSavedFolder {
                    Button("Forget folder access", role: .destructive) {
                        manager.forgetCodexFolder()
                    }
                }

                if manager.errorMessage == nil {
                    Text(manager.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(manager.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Live activity")
            } footer: {
                Text("Boring Notch checks the local Codex databases every two seconds. It reads task titles and active turn status through read-only SQLite connections; it does not read prompts or responses.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Codex")
    }
}
