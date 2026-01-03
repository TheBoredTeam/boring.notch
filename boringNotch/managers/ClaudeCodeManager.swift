//
//  ClaudeCodeManager.swift
//  boringNotch
//
//  Created for Claude Code Notch integration
//

import Foundation
import Combine
import UserNotifications
import AppKit

@MainActor
final class ClaudeCodeManager: ObservableObject {
    static let shared = ClaudeCodeManager()

    // MARK: - Cached Formatters (expensive to create repeatedly)
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Published Properties

    @Published private(set) var availableSessions: [ClaudeSession] = []
    @Published var selectedSession: ClaudeSession?
    @Published private(set) var state: ClaudeCodeState = ClaudeCodeState()
    @Published private(set) var dailyStats: DailyStats = DailyStats()

    // MARK: - Multi-Session Permission Tracking

    /// Per-session state tracking for permission detection
    @Published private(set) var sessionStates: [String: ClaudeCodeState] = [:]

    /// Sessions currently waiting for user permission approval
    @Published private(set) var sessionsNeedingPermission: [ClaudeSession] = []

    /// Track when we last had activity (for grace period before notch collapses)
    private var lastActivityTime: Date = Date()
    /// Grace period to keep notch visible after activity stops (seconds)
    private let activityGracePeriod: TimeInterval = 2.0

    /// True if any session has activity (thinking, active tools, or needs permission)
    /// Includes a grace period to prevent flickering when switching between tools
    var hasAnySessionActivity: Bool {
        // Check if any session is active (thinking or has active tools) or needs permission
        for sessionState in sessionStates.values {
            if sessionState.isActive || sessionState.needsPermission {
                lastActivityTime = Date()
                return true
            }
        }
        // Also check selected session's state
        if state.isActive || state.needsPermission {
            lastActivityTime = Date()
            return true
        }
        if !sessionsNeedingPermission.isEmpty {
            lastActivityTime = Date()
            return true
        }

        // Grace period: keep showing activity for a short time after it stops
        // This prevents the notch from flickering during tool transitions
        let timeSinceLastActivity = Date().timeIntervalSince(lastActivityTime)
        if timeSinceLastActivity < activityGracePeriod {
            return true
        }

        return false
    }

    // MARK: - Private Properties

    // Use the real home directory, not the sandboxed container
    private let claudeDir: URL = {
        // Get the real home directory by reading from passwd, bypassing sandbox
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            let homePath = String(cString: home)
            return URL(fileURLWithPath: homePath).appendingPathComponent(".claude")
        }
        // Fallback to standard (will be sandboxed)
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }()
    private var ideDir: URL { claudeDir.appendingPathComponent("ide") }
    private var projectsDir: URL { claudeDir.appendingPathComponent("projects") }

    private var sessionFileWatcher: DispatchSourceFileSystemObject?
    private var ideDirWatcher: DispatchSourceFileSystemObject?
    private var sessionFileHandle: FileHandle?
    private var lastReadPosition: UInt64 = 0

    private var sessionScanTimer: Timer?

    /// Timer to detect when a tool is waiting for permission (no result after delay)
    private var permissionCheckTimer: Timer?
    /// Tracks tool IDs that we're waiting on for permission check (for selected session - legacy)
    private var pendingToolChecks: [String: Date] = [:]
    /// Delay before assuming a tool needs permission (seconds)
    private let permissionCheckDelay: TimeInterval = 2.5
    /// Flag to disable permission tracking during history loading
    private var isLoadingHistory: Bool = false

    // MARK: - Multi-Session Watching (for permission detection across all sessions)

    /// File watchers for all active sessions (keyed by session.id)
    private var sessionWatchers: [String: DispatchSourceFileSystemObject] = [:]
    /// File handles for all active sessions
    private var sessionFileHandles: [String: FileHandle] = [:]
    /// Read positions for all active sessions
    private var sessionReadPositions: [String: UInt64] = [:]
    /// Pending tool checks per session: [sessionId: [toolId: startTime]]
    private var pendingToolChecksBySession: [String: [String: Date]] = [:]
    /// History loading flag per session
    private var isLoadingHistoryBySession: [String: Bool] = [:]
    /// Timer to detect idle state (no activity for a while = Claude is done)
    private var idleCheckTimer: Timer?
    /// Delay before assuming Claude is idle (seconds)
    /// Set higher to prevent flickering between tool calls
    private let idleCheckDelay: TimeInterval = 8.0

    // MARK: - Initialization

    private init() {
        setupNotifications()
        startSessionScanning()
        loadDailyStats()
    }

    // Note: cleanup is handled by stopWatching() called manually or when app terminates

    // MARK: - Public Methods

    /// Scan for active Claude Code sessions
    func scanForSessions() {
        let fm = FileManager.default

        guard fm.fileExists(atPath: ideDir.path) else {
            availableSessions = []
            return
        }

        do {
            let lockFiles = try fm.contentsOfDirectory(at: ideDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "lock" }

            var sessions: [ClaudeSession] = []

            for lockFile in lockFiles {
                guard let data = fm.contents(atPath: lockFile.path) else {
                    continue
                }

                do {
                    let session = try JSONDecoder().decode(ClaudeSession.self, from: data)

                    // Verify process is still running
                    if isProcessRunning(pid: session.pid) {
                        sessions.append(session)
                    }
                } catch {
                    // Skip invalid lock files silently
                }
            }

            // Only log when session count changes
            if sessions.count != availableSessions.count {
                print("[ClaudeCode] Active sessions: \(sessions.count)")
            }
            availableSessions = sessions

            // Auto-select if only one session and none selected
            if selectedSession == nil && sessions.count == 1 {
                selectSession(sessions[0])
            }

            // Clear selection if selected session no longer exists
            if let selected = selectedSession,
               !sessions.contains(where: { $0.pid == selected.pid }) {
                selectedSession = nil
                state = ClaudeCodeState()
                stopWatchingSessionFile()
            }

            // MARK: Multi-Session Watching - Watch ALL sessions for permission detection
            let currentSessionIds = Set(sessions.map { $0.id })

            // Start watching new sessions
            for session in sessions {
                if sessionWatchers[session.id] == nil {
                    startWatchingSession(session)
                }
            }

            // Stop watching sessions that no longer exist
            let watchedIds = Array(sessionWatchers.keys)
            for watchedId in watchedIds where !currentSessionIds.contains(watchedId) {
                stopWatchingSession(id: watchedId)
            }

        } catch {
            print("[ClaudeCode] Error scanning for sessions: \(error)")
        }
    }

    /// Select a session to monitor
    func selectSession(_ session: ClaudeSession) {
        guard session != selectedSession else { return }

        print("[ClaudeCode] Selecting session: \(session.displayName)")
        selectedSession = session
        state = ClaudeCodeState()
        state.cwd = session.workspaceFolders.first ?? ""

        startWatchingSessionFile()
    }

    /// Manually refresh state
    func refresh() {
        scanForSessions()
        if selectedSession != nil {
            readNewSessionData()
        }
    }

    // MARK: - Session Scanning

    private func startSessionScanning() {
        // Initial scan
        scanForSessions()

        // Periodic scan every 10 seconds (reduced from 5 to minimize memory pressure)
        sessionScanTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanForSessions()
                self?.loadDailyStats()
            }
        }
    }

    private func isProcessRunning(pid: Int) -> Bool {
        // Use NSRunningApplication or check /proc to avoid sandbox restrictions with kill()
        // The kill() approach doesn't work in sandboxed apps
        let runningApps = NSWorkspace.shared.runningApplications
        if runningApps.contains(where: { $0.processIdentifier == Int32(pid) }) {
            return true
        }

        // Fallback: check if the process directory exists (works for any process)
        let procPath = "/proc/\(pid)"
        if FileManager.default.fileExists(atPath: procPath) {
            return true
        }

        // Another fallback: try to get process info via sysctl
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)

        // If sysctl succeeds and returns data, process exists
        return result == 0 && size > 0
    }

    // MARK: - File Watching

    private func startWatchingSessionFile() {
        stopWatchingSessionFile()

        guard let session = selectedSession,
              let projectKey = session.projectKey else {
            print("[ClaudeCode] No session or projectKey available")
            return
        }

        print("[ClaudeCode] Looking for project dir with key: \(projectKey)")
        let projectDir = projectsDir.appendingPathComponent(projectKey)
        print("[ClaudeCode] Project dir path: \(projectDir.path)")
        print("[ClaudeCode] Project dir exists: \(FileManager.default.fileExists(atPath: projectDir.path))")

        // Find the most recent JSONL file (not agent files)
        guard let jsonlFile = findCurrentSessionFile(in: projectDir) else {
            print("[ClaudeCode] No session file found for project: \(projectKey)")
            return
        }

        print("[ClaudeCode] Watching session file: \(jsonlFile.path)")

        // Open file for reading
        do {
            sessionFileHandle = try FileHandle(forReadingFrom: jsonlFile)

            // Seek to end to only read new content
            sessionFileHandle?.seekToEndOfFile()
            lastReadPosition = sessionFileHandle?.offsetInFile ?? 0

            // But first, read recent history for initial state
            loadRecentHistory(from: jsonlFile)

        } catch {
            print("Error opening session file: \(error)")
            return
        }

        // Set up file system watcher
        let fd = open(jsonlFile.path, O_EVTONLY)
        guard fd >= 0 else {
            print("Failed to open file descriptor for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.readNewSessionData()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sessionFileWatcher = source
        state.isConnected = true
    }

    private func stopWatchingSessionFile() {
        sessionFileWatcher?.cancel()
        sessionFileWatcher = nil
        sessionFileHandle?.closeFile()
        sessionFileHandle = nil
        lastReadPosition = 0
        state.isConnected = false
    }

    private func stopWatching() {
        sessionScanTimer?.invalidate()
        sessionScanTimer = nil
        idleCheckTimer?.invalidate()
        idleCheckTimer = nil
        stopWatchingSessionFile()
        ideDirWatcher?.cancel()
        ideDirWatcher = nil

        // Stop all multi-session watchers
        for sessionId in sessionWatchers.keys {
            stopWatchingSession(id: sessionId)
        }
    }

    // MARK: - Multi-Session Watching (Permission Detection for All Sessions)

    /// Start watching a specific session for permission detection
    private func startWatchingSession(_ session: ClaudeSession) {
        guard sessionWatchers[session.id] == nil,
              let projectKey = session.projectKey else {
            return
        }

        let projectDir = projectsDir.appendingPathComponent(projectKey)
        guard let jsonlFile = findCurrentSessionFile(in: projectDir) else {
            print("[ClaudeCode-Multi] No session file found for: \(session.displayName)")
            return
        }

        print("[ClaudeCode-Multi] Starting to watch session: \(session.displayName)")

        // Initialize state for this session
        var sessionState = ClaudeCodeState()
        sessionState.cwd = session.workspaceFolders.first ?? ""
        sessionState.isConnected = true
        sessionStates[session.id] = sessionState

        // Open file handle
        do {
            let handle = try FileHandle(forReadingFrom: jsonlFile)
            handle.seekToEndOfFile()
            sessionFileHandles[session.id] = handle
            sessionReadPositions[session.id] = handle.offsetInFile

            // Load recent history for initial state
            loadRecentHistoryForSession(from: jsonlFile, sessionId: session.id)

        } catch {
            print("[ClaudeCode-Multi] Error opening session file: \(error)")
            return
        }

        // Set up file system watcher
        let fd = open(jsonlFile.path, O_EVTONLY)
        guard fd >= 0 else {
            print("[ClaudeCode-Multi] Failed to open file descriptor for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.readNewSessionDataForSession(sessionId: session.id)
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sessionWatchers[session.id] = source
    }

    /// Stop watching a specific session
    private func stopWatchingSession(id sessionId: String) {
        sessionWatchers[sessionId]?.cancel()
        sessionWatchers.removeValue(forKey: sessionId)
        sessionFileHandles[sessionId]?.closeFile()
        sessionFileHandles.removeValue(forKey: sessionId)
        sessionReadPositions.removeValue(forKey: sessionId)
        sessionStates.removeValue(forKey: sessionId)
        pendingToolChecksBySession.removeValue(forKey: sessionId)
        isLoadingHistoryBySession.removeValue(forKey: sessionId)

        // Update sessionsNeedingPermission
        sessionsNeedingPermission.removeAll { $0.id == sessionId }

        print("[ClaudeCode-Multi] Stopped watching session: \(sessionId)")
    }

    /// Load recent history for a specific session
    private func loadRecentHistoryForSession(from file: URL, sessionId: String) {
        // Read only the last ~50KB of the file to get recent lines (avoids loading huge files into memory)
        let maxBytesToRead: UInt64 = 50 * 1024  // 50KB should be plenty for last 50 lines

        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return
        }
        defer { try? handle.close() }

        // Seek to near the end of the file
        let fileSize = handle.seekToEndOfFile()
        let startPosition = fileSize > maxBytesToRead ? fileSize - maxBytesToRead : 0
        handle.seek(toFileOffset: startPosition)

        guard let data = try? handle.readToEnd(),
              let content = String(data: data, encoding: .utf8) else {
            return
        }

        let lines = content.components(separatedBy: .newlines)
        // Skip first line if we started mid-file (it might be truncated)
        let linesToProcess = startPosition > 0 ? Array(lines.dropFirst().suffix(50)) : Array(lines.suffix(50))

        // Disable permission tracking during history loading
        isLoadingHistoryBySession[sessionId] = true
        for line in linesToProcess where !line.isEmpty {
            parseJSONLLineForSession(line, sessionId: sessionId)
        }
        isLoadingHistoryBySession[sessionId] = false

        // Clear any active state from history - they're already done
        sessionStates[sessionId]?.activeTools.removeAll()
        sessionStates[sessionId]?.isThinking = false
        pendingToolChecksBySession[sessionId]?.removeAll()
    }

    /// Read new data for a specific session
    private func readNewSessionDataForSession(sessionId: String) {
        guard let handle = sessionFileHandles[sessionId],
              let lastPosition = sessionReadPositions[sessionId] else { return }

        handle.seek(toFileOffset: lastPosition)
        let newData = handle.readDataToEndOfFile()
        sessionReadPositions[sessionId] = handle.offsetInFile

        guard !newData.isEmpty,
              let content = String(data: newData, encoding: .utf8) else { return }

        // Any file activity means Claude is working (including compacting/summarizing)
        // Set isThinking immediately when we detect new data being written
        sessionStates[sessionId]?.isThinking = true

        let lines = content.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            parseJSONLLineForSession(line, sessionId: sessionId)
        }

        sessionStates[sessionId]?.lastUpdateTime = Date()

        // Reset idle timer - we just got activity
        resetIdleTimer()
    }

    /// Reset the idle detection timer
    private func resetIdleTimer() {
        idleCheckTimer?.invalidate()
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: idleCheckDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.markAllSessionsIdle()
            }
        }
    }

    /// Mark all sessions as idle (no activity for a while)
    private func markAllSessionsIdle() {
        for sessionId in sessionStates.keys {
            // Only mark idle if not waiting for permission
            if sessionStates[sessionId]?.needsPermission != true {
                sessionStates[sessionId]?.isThinking = false
            }
        }
        // Also mark selected session as idle
        if !state.needsPermission {
            state.isThinking = false
        }
    }

    /// Parse a JSONL line for a specific session (focused on permission detection)
    private func parseJSONLLineForSession(_ line: String, sessionId: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Parse message content for tool detection
        if let message = json["message"] as? [String: Any] {
            parseMessageForSession(message, sessionId: sessionId)
        }
    }

    /// Parse message content for a specific session
    private func parseMessageForSession(_ message: [String: Any], sessionId: String) {
        // Extract model
        if let model = message["model"] as? String {
            sessionStates[sessionId]?.model = model
        }

        // Track thinking state based on message role
        // Key insight: Claude logs messages AFTER they're complete
        // - User message logged = Claude is about to think/respond
        // - Assistant message logged = Claude finished responding (idle timer will mark idle)
        // - Tool_result = Claude will continue thinking after tool executes
        if let role = message["role"] as? String {
            if role == "user" {
                // User message logged - Claude is about to respond
                // Check if this is a tool_result (continues thinking) or new prompt (starts thinking)
                var hasToolResult = false
                if let content = message["content"] as? [[String: Any]] {
                    hasToolResult = content.contains { ($0["type"] as? String) == "tool_result" }
                }
                // Either way, Claude is now thinking (responding to user or continuing after tool)
                sessionStates[sessionId]?.isThinking = true
            } else if role == "assistant" {
                // Assistant message logged = Claude finished this response
                // Keep isThinking true - the idle timer will set it to false after delay
                // This prevents the dot from flickering between responses
                sessionStates[sessionId]?.isThinking = true
            }
        }

        // Extract message content for tool_use detection
        if let content = message["content"] as? [[String: Any]] {
            for item in content {
                if let type = item["type"] as? String {
                    switch type {
                    case "tool_use":
                        if let toolId = item["id"] as? String,
                           let toolName = item["name"] as? String {
                            let tool = ToolExecution(
                                id: toolId,
                                toolName: toolName,
                                argument: extractToolArgument(from: item["input"]),
                                startTime: Date()
                            )
                            if sessionStates[sessionId]?.activeTools.contains(where: { $0.id == toolId }) != true {
                                sessionStates[sessionId]?.activeTools.append(tool)
                                startPermissionCheckForSession(sessionId: sessionId, toolId: toolId, toolName: toolName)
                            }
                        }

                    default:
                        break
                    }
                }
            }
        }

        // Check for tool_result in user messages to mark tools as complete
        if let role = message["role"] as? String, role == "user",
           let content = message["content"] as? [[String: Any]] {
            for item in content {
                if let type = item["type"] as? String, type == "tool_result",
                   let toolUseId = item["tool_use_id"] as? String {
                    clearPermissionCheckForSession(sessionId: sessionId, toolId: toolUseId)

                    // Mark tool as complete
                    if let index = sessionStates[sessionId]?.activeTools.firstIndex(where: { $0.id == toolUseId }) {
                        sessionStates[sessionId]?.activeTools.remove(at: index)
                    }

                    // IMPORTANT: Set isThinking=true immediately after tool completion
                    // Claude will always respond after receiving a tool result, so we stay active
                    sessionStates[sessionId]?.isThinking = true
                }
            }
        }
    }

    /// Start tracking a tool for permission check in a specific session
    private func startPermissionCheckForSession(sessionId: String, toolId: String, toolName: String) {
        guard isLoadingHistoryBySession[sessionId] != true else { return }

        pendingToolChecksBySession[sessionId, default: [:]][toolId] = Date()

        // Start or restart the permission check timer
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: permissionCheckDelay, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPendingPermissionsForAllSessions()
            }
        }
    }

    /// Clear permission tracking for a tool in a specific session
    private func clearPermissionCheckForSession(sessionId: String, toolId: String) {
        pendingToolChecksBySession[sessionId]?.removeValue(forKey: toolId)

        // If this session was showing permission needed, clear it
        if sessionStates[sessionId]?.needsPermission == true {
            if pendingToolChecksBySession[sessionId]?.isEmpty ?? true {
                sessionStates[sessionId]?.needsPermission = false
                sessionStates[sessionId]?.pendingPermissionTool = nil
            }
        }

        // Update sessionsNeedingPermission
        updateSessionsNeedingPermission()
    }

    /// Check all sessions for pending permissions
    private func checkPendingPermissionsForAllSessions() {
        let now = Date()

        for (sessionId, toolChecks) in pendingToolChecksBySession {
            for (toolId, startTime) in toolChecks {
                let elapsed = now.timeIntervalSince(startTime)
                if elapsed >= permissionCheckDelay {
                    // This tool has been pending too long - likely needs permission
                    if let tool = sessionStates[sessionId]?.activeTools.first(where: { $0.id == toolId }) {
                        sessionStates[sessionId]?.needsPermission = true
                        sessionStates[sessionId]?.pendingPermissionTool = tool.toolName
                        break
                    }
                }
            }
        }

        updateSessionsNeedingPermission()

        // Stop timer if no more pending tools across all sessions
        let hasPendingTools = pendingToolChecksBySession.values.contains { !$0.isEmpty }
        if !hasPendingTools {
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
        }
    }

    /// Update the sessionsNeedingPermission array based on current state
    private func updateSessionsNeedingPermission() {
        var needingPermission: [ClaudeSession] = []

        for session in availableSessions {
            if sessionStates[session.id]?.needsPermission == true {
                needingPermission.append(session)
            }
        }

        // Also check the selected session's state
        if state.needsPermission, let selected = selectedSession {
            if !needingPermission.contains(where: { $0.id == selected.id }) {
                needingPermission.append(selected)
            }
        }

        sessionsNeedingPermission = needingPermission
    }

    private func findCurrentSessionFile(in projectDir: URL) -> URL? {
        let fm = FileManager.default

        guard fm.fileExists(atPath: projectDir.path) else { return nil }

        do {
            let files = try fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "jsonl" && !$0.lastPathComponent.hasPrefix("agent-") }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    return date1 > date2
                }

            return files.first
        } catch {
            print("Error finding session file: \(error)")
            return nil
        }
    }

    // MARK: - Data Reading

    private func loadRecentHistory(from file: URL) {
        // Read only the last ~50KB of the file to get recent lines (avoids loading huge files into memory)
        let maxBytesToRead: UInt64 = 50 * 1024  // 50KB should be plenty for last 50 lines

        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return
        }
        defer { try? handle.close() }

        // Seek to near the end of the file
        let fileSize = handle.seekToEndOfFile()
        let startPosition = fileSize > maxBytesToRead ? fileSize - maxBytesToRead : 0
        handle.seek(toFileOffset: startPosition)

        guard let data = try? handle.readToEnd(),
              let content = String(data: data, encoding: .utf8) else {
            return
        }

        let lines = content.components(separatedBy: .newlines)
        // Skip first line if we started mid-file (it might be truncated)
        let linesToProcess = startPosition > 0 ? Array(lines.dropFirst().suffix(50)) : Array(lines.suffix(50))

        // Disable permission tracking during history loading - these are already completed tools
        isLoadingHistory = true
        for line in linesToProcess where !line.isEmpty {
            parseJSONLLine(line)
        }
        isLoadingHistory = false

        // Clear any active state from history - they're already done
        state.activeTools.removeAll()
        state.isThinking = false
        pendingToolChecks.removeAll()

        state.lastUpdateTime = Date()
    }

    private func readNewSessionData() {
        guard let handle = sessionFileHandle else { return }

        // Read new data from last position
        handle.seek(toFileOffset: lastReadPosition)
        let newData = handle.readDataToEndOfFile()
        lastReadPosition = handle.offsetInFile

        guard !newData.isEmpty,
              let content = String(data: newData, encoding: .utf8) else { return }

        // Any file activity means Claude is working (including compacting/summarizing)
        // Set isThinking immediately when we detect new data being written
        state.isThinking = true

        let lines = content.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            parseJSONLLine(line)
        }

        state.lastUpdateTime = Date()

        // Reset idle timer - we just got activity
        resetIdleTimer()
    }

    // MARK: - JSONL Parsing

    private func parseJSONLLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Extract session info
        if let sessionId = json["sessionId"] as? String {
            state.sessionId = sessionId
        }
        if let cwd = json["cwd"] as? String {
            state.cwd = cwd
        }
        if let gitBranch = json["gitBranch"] as? String {
            state.gitBranch = gitBranch
        }

        // Parse message content
        if let message = json["message"] as? [String: Any] {
            parseMessage(message)
        }

        // Parse tool use results
        if json["toolUseResult"] != nil {
            // Tool completed - could track timing here
        }
    }

    private func parseMessage(_ message: [String: Any]) {
        // Extract model
        if let model = message["model"] as? String {
            state.model = model
        }

        // Track thinking state based on message role
        // Key insight: Claude logs messages AFTER they're complete
        // - User message logged = Claude is about to think/respond
        // - Assistant message logged = Claude finished responding (idle timer will mark idle)
        if let role = message["role"] as? String {
            if role == "user" {
                // User message logged - Claude is about to respond
                state.isThinking = true
            } else if role == "assistant" {
                // Assistant message logged = Claude finished this response
                // Keep isThinking true - the idle timer will set it to false after delay
                state.isThinking = true
            }
        }

        // Extract token usage
        if let usage = message["usage"] as? [String: Any] {
            state.tokenUsage.inputTokens = usage["input_tokens"] as? Int ?? state.tokenUsage.inputTokens
            state.tokenUsage.outputTokens = usage["output_tokens"] as? Int ?? state.tokenUsage.outputTokens
            state.tokenUsage.cacheReadInputTokens = usage["cache_read_input_tokens"] as? Int ?? state.tokenUsage.cacheReadInputTokens
            state.tokenUsage.cacheCreationInputTokens = usage["cache_creation_input_tokens"] as? Int ?? state.tokenUsage.cacheCreationInputTokens
        }

        // Extract message content
        if let content = message["content"] as? [[String: Any]] {
            for item in content {
                if let type = item["type"] as? String {
                    switch type {
                    case "text":
                        if let text = item["text"] as? String {
                            // Get first line or first 100 chars as preview
                            let preview = text.components(separatedBy: .newlines).first ?? text
                            state.lastMessage = String(preview.prefix(100))
                            state.lastMessageTime = Date()
                        }

                    case "tool_use":
                        if let toolId = item["id"] as? String,
                           let toolName = item["name"] as? String {

                            // Parse TodoWrite tool to extract todos
                            if toolName == "TodoWrite",
                               let input = item["input"] as? [String: Any],
                               let todos = input["todos"] as? [[String: Any]] {
                                parseTodos(todos)
                            }

                            let tool = ToolExecution(
                                id: toolId,
                                toolName: toolName,
                                argument: extractToolArgument(from: item["input"]),
                                startTime: Date()
                            )
                            // Add to active tools
                            if !state.activeTools.contains(where: { $0.id == toolId }) {
                                state.activeTools.append(tool)
                                // Start tracking this tool for permission check
                                startPermissionCheck(toolId: toolId, toolName: toolName)
                            }
                        }

                    default:
                        break
                    }
                }
            }
        }

        // Check for tool_result in user messages to mark tools as complete
        if let role = message["role"] as? String, role == "user",
           let content = message["content"] as? [[String: Any]] {
            for item in content {
                if let type = item["type"] as? String, type == "tool_result",
                   let toolUseId = item["tool_use_id"] as? String {
                    // Clear permission tracking for this tool
                    clearPermissionCheck(toolId: toolUseId)

                    // Mark tool as complete
                    if let index = state.activeTools.firstIndex(where: { $0.id == toolUseId }) {
                        var tool = state.activeTools.remove(at: index)
                        tool.endTime = Date()
                        state.recentTools.insert(tool, at: 0)
                        // Keep only last 10 recent tools
                        if state.recentTools.count > 10 {
                            state.recentTools.removeLast()
                        }
                    }

                    // IMPORTANT: Set isThinking=true immediately after tool completion
                    // Claude will always respond after receiving a tool result, so we stay active
                    state.isThinking = true
                }
            }
        }
    }

    private func extractToolArgument(from input: Any?) -> String? {
        guard let input = input as? [String: Any] else { return nil }

        // Common argument names
        if let pattern = input["pattern"] as? String { return pattern }
        if let command = input["command"] as? String { return String(command.prefix(50)) }
        if let filePath = input["file_path"] as? String { return URL(fileURLWithPath: filePath).lastPathComponent }
        if let query = input["query"] as? String { return String(query.prefix(50)) }
        if let prompt = input["prompt"] as? String { return String(prompt.prefix(50)) }

        return nil
    }

    private func parseTodos(_ todosArray: [[String: Any]]) {
        var newTodos: [ClaudeTodoItem] = []

        for todoDict in todosArray {
            guard let content = todoDict["content"] as? String,
                  let statusStr = todoDict["status"] as? String else {
                continue
            }

            let status: ClaudeTodoItem.TodoStatus
            switch statusStr {
            case "pending":
                status = .pending
            case "in_progress":
                status = .inProgress
            case "completed":
                status = .completed
            default:
                status = .pending
            }

            newTodos.append(ClaudeTodoItem(content: content, status: status))
        }

        // Replace the entire todo list (TodoWrite always sends the complete list)
        state.todos = newTodos
    }

    // MARK: - Permission Detection

    /// Start tracking a tool to check if it needs permission
    private func startPermissionCheck(toolId: String, toolName: String) {
        // Don't track permission during history loading - those tools are already completed
        guard !isLoadingHistory else {
            return
        }

        pendingToolChecks[toolId] = Date()

        // Start or restart the permission check timer
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: permissionCheckDelay, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPendingPermissions()
            }
        }
    }

    /// Clear permission tracking for a tool (when it completes)
    private func clearPermissionCheck(toolId: String) {
        pendingToolChecks.removeValue(forKey: toolId)

        // If we were showing permission needed for this tool, clear it
        if state.needsPermission {
            // Check if any other tools still need permission
            if pendingToolChecks.isEmpty {
                state.needsPermission = false
                state.pendingPermissionTool = nil
                permissionCheckTimer?.invalidate()
                permissionCheckTimer = nil
            } else {
                // Re-check if any remaining tools need permission
                checkPendingPermissions()
            }
        }

        // Stop timer if no more pending tools
        if pendingToolChecks.isEmpty {
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
        }
    }

    /// Check if any pending tools have exceeded the delay (likely waiting for permission)
    private func checkPendingPermissions() {
        let now = Date()

        for (toolId, startTime) in pendingToolChecks {
            let elapsed = now.timeIntervalSince(startTime)
            if elapsed >= permissionCheckDelay {
                // This tool has been pending too long - likely needs permission
                if let tool = state.activeTools.first(where: { $0.id == toolId }) {
                    if !state.needsPermission {
                        print("[ClaudeCode] ⚠️ Tool '\(tool.toolName)' waiting for permission")
                    }
                    state.needsPermission = true
                    state.pendingPermissionTool = tool.toolName
                    return
                } else {
                    // Tool not in activeTools - still show permission indicator
                    if !state.needsPermission {
                        state.needsPermission = true
                        state.pendingPermissionTool = "Tool"
                    }
                    return
                }
            }
        }
    }

    // MARK: - IDE Focus

    /// Bring the IDE running Claude Code to the front
    /// - Parameter session: The session to focus. If nil, focuses the selected session.
    func focusIDE(for session: ClaudeSession? = nil) {
        guard let targetSession = session ?? selectedSession else {
            print("[ClaudeCode] No session to focus")
            return
        }

        let ideName = targetSession.ideName.lowercased()
        print("[ClaudeCode] Attempting to focus IDE: \(targetSession.ideName)")

        // Map common IDE names to bundle identifiers
        let bundleIdentifiers: [String] = {
            if ideName.contains("cursor") {
                return ["com.todesktop.230313mzl4w4u92"]
            } else if ideName.contains("code") || ideName.contains("vscode") {
                return ["com.microsoft.VSCode", "com.visualstudio.code.oss"]
            } else if ideName.contains("windsurf") {
                return ["com.codeium.windsurf"]
            } else if ideName.contains("zed") {
                return ["dev.zed.Zed"]
            } else {
                // Try to find by process ID as fallback
                return []
            }
        }()

        // Try to activate by bundle identifier first
        for bundleId in bundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                print("[ClaudeCode] Found app by bundle ID: \(bundleId)")
                app.activate(options: [.activateIgnoringOtherApps])
                return
            }
        }

        // Fallback: find by PID
        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: { $0.processIdentifier == Int32(targetSession.pid) }) {
            print("[ClaudeCode] Found app by PID: \(targetSession.pid)")
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }

        // Last resort: try to find any app with matching name
        if let app = runningApps.first(where: {
            $0.localizedName?.lowercased().contains(ideName) == true
        }) {
            print("[ClaudeCode] Found app by name match: \(app.localizedName ?? "unknown")")
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }

        print("[ClaudeCode] Could not find IDE to focus")
    }

    // MARK: - Notifications

    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyAgentCompletion(agent: AgentInfo) {
        let content = UNMutableNotificationContent()
        content.title = "Agent Completed"
        content.body = "\(agent.name): \(agent.description)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Daily Stats

    /// Load daily stats from ~/.claude/stats-cache.json
    func loadDailyStats() {
        let statsFile = claudeDir.appendingPathComponent("stats-cache.json")

        guard FileManager.default.fileExists(atPath: statsFile.path),
              let data = FileManager.default.contents(atPath: statsFile.path) else {
            return
        }

        do {
            let cache = try JSONDecoder().decode(StatsCache.self, from: data)

            // Get today's date in the format used by the cache (YYYY-MM-DD)
            let today = Self.dateFormatter.string(from: Date())

            var stats = DailyStats()

            // Try to find today's activity first, otherwise get the most recent
            let sortedActivity = cache.dailyActivity?.sorted { $0.date > $1.date }
            if let todayActivity = sortedActivity?.first(where: { $0.date == today }) {
                stats.date = today
                stats.messageCount = todayActivity.messageCount ?? 0
                stats.toolCallCount = todayActivity.toolCallCount ?? 0
                stats.sessionCount = todayActivity.sessionCount ?? 0
            } else if let latestActivity = sortedActivity?.first {
                // Use most recent day's stats
                stats.date = latestActivity.date
                stats.messageCount = latestActivity.messageCount ?? 0
                stats.toolCallCount = latestActivity.toolCallCount ?? 0
                stats.sessionCount = latestActivity.sessionCount ?? 0
            }

            // Try to find today's token usage first, otherwise get the most recent
            let sortedTokens = cache.dailyModelTokens?.sorted { $0.date > $1.date }
            let targetDate = stats.date.isEmpty ? today : stats.date
            if let dayTokens = sortedTokens?.first(where: { $0.date == targetDate }),
               let tokensByModel = dayTokens.tokensByModel {
                stats.tokensUsed = tokensByModel.values.reduce(0, +)
            } else if let latestTokens = sortedTokens?.first,
                      let tokensByModel = latestTokens.tokensByModel {
                stats.tokensUsed = tokensByModel.values.reduce(0, +)
                if stats.date.isEmpty {
                    stats.date = latestTokens.date
                }
            }

            // Only update and log if stats changed
            if stats != dailyStats {
                dailyStats = stats
            }

        } catch {
            print("[ClaudeCode] Error parsing stats-cache.json: \(error)")
        }
    }
}
