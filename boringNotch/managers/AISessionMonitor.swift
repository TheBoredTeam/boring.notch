//
//  AISessionMonitor.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Defaults
import Foundation
import UserNotifications

struct AISessionCompletion: Identifiable, Equatable {
    let id: String
    let source: AISessionSource
    let projectName: String
    let completedAt: Date
}

@MainActor
final class AISessionMonitor: ObservableObject {
    static let shared = AISessionMonitor()

    @Published private(set) var sessions: [AISessionRecord] = []
    @Published private(set) var completions: [AISessionCompletion] = []
    @Published private(set) var isLoading = false

    private var scanTask: Task<Void, Never>?
    private var hasScanned = false
    private let retention: TimeInterval = 30 * 60

    private var snapshotURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Boring Notch/ai-session-snapshot.json")
    }

    private init() {}

    func updateEnabled() {
        guard Defaults[.enableAISessionFeature] else {
            scanTask?.cancel()
            scanTask = nil
            sessions = []
            completions = []
            hasScanned = false
            isLoading = false
            clearSnapshot()
            return
        }
        guard scanTask == nil else { return }
        restoreSnapshot()
        isLoading = true
        scanTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refresh()
                let hasRecentWork = self.sessions.contains {
                    $0.status == .working || Date().timeIntervalSince($0.lastActivity) < 300
                }
                try? await Task.sleep(for: .seconds(hasRecentWork ? 3 : 15))
            }
        }
    }

    func refresh() async {
        guard Defaults[.enableAISessionFeature] else { return }
        let scanned = await Task.detached(priority: .utility) {
            AISessionScanner.scan()
        }.value
        guard !Task.isCancelled, Defaults[.enableAISessionFeature] else { return }
        let now = Date()
        let previous = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        if hasScanned {
            let newCompletions = Self.completedSessions(before: previous, after: scanned, at: now)
            completions = Array((newCompletions + completions).prefix(20))
            if Defaults[.enableAISessionCompletionNotifications] {
                for completion in newCompletions { postNotification(for: completion) }
            }
        }
        sessions = Self.reconcile(scanned: scanned, previous: sessions, at: now, retention: retention)
        hasScanned = true
        isLoading = false
        persistSnapshot()
    }

    func dismissCompletion(id: String) {
        completions.removeAll { $0.id == id }
    }

    func ingestOpenClaw(
        sessionID: String, event: String, cwd: String?, message: String?, at time: Date = Date()
    ) {
        guard Defaults[.enableAISessionFeature], !sessionID.isEmpty else { return }
        let id = "openclaw:\(sessionID)"
        let old = sessions.first { $0.id == id }
        let status: AISessionStatus
        switch event {
        case "SessionEnd", "Stop", "AfterAgentResponse": status = .idle
        case "SessionStart", "UserPromptSubmit", "PermissionRequest", "AskUserQuestion", "PreToolUse":
            status = .working
        default: status = old?.status ?? .idle
        }
        var prompt = old?.latestPrompt
        var reply = old?.latestReply
        if event == "UserPromptSubmit", let message { prompt = String(message.prefix(400)) }
        if event == "AfterAgentResponse", let message { reply = String(message.prefix(400)) }
        let path = cwd ?? old?.cwd
        let session = AISessionRecord(
            id: id, source: .openClaw,
            projectName: path.map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? old?.projectName ?? "OpenClaw",
            status: status, lastActivity: time,
            latestMessage: reply ?? prompt,
            isDesktopSession: false, cwd: path,
            latestPrompt: prompt, latestReply: reply,
            terminalBundleID: old?.terminalBundleID,
            windowTitle: old?.windowTitle,
            currentTool: old?.currentTool
        )
        if let old, old.status == .working, status == .idle {
            let completion = AISessionCompletion(
                id: id, source: .openClaw,
                projectName: session.projectName, completedAt: time
            )
            completions.insert(completion, at: 0)
            if Defaults[.enableAISessionCompletionNotifications] {
                postNotification(for: completion)
            }
        }
        sessions.removeAll { $0.id == id }
        sessions.append(session)
        sessions.sort { $0.lastActivity > $1.lastActivity }
        persistSnapshot()
    }

    nonisolated static func reconcile(
        scanned: [AISessionRecord], previous: [AISessionRecord], at now: Date,
        retention: TimeInterval = 30 * 60
    ) -> [AISessionRecord] {
        var byID = Dictionary(uniqueKeysWithValues: previous
            .filter { now.timeIntervalSince($0.lastActivity) < retention }
            .map { ($0.id, $0) })
        for session in scanned where now.timeIntervalSince(session.lastActivity) < retention {
            if let cached = byID[session.id], cached.lastActivity > session.lastActivity {
                continue
            }
            if let cached = byID[session.id] {
                byID[session.id] = AISessionRecord(
                    id: session.id, source: session.source,
                    projectName: session.projectName,
                    status: session.status, lastActivity: session.lastActivity,
                    latestMessage: session.latestMessage ?? cached.latestMessage,
                    isDesktopSession: session.isDesktopSession,
                    cwd: session.cwd ?? cached.cwd,
                    latestPrompt: session.latestPrompt ?? cached.latestPrompt,
                    latestReply: session.latestReply ?? cached.latestReply,
                    terminalBundleID: session.terminalBundleID ?? cached.terminalBundleID,
                    windowTitle: session.windowTitle ?? cached.windowTitle,
                    currentTool: session.currentTool ?? cached.currentTool
                )
            } else {
                byID[session.id] = session
            }
        }
        return byID.values.sorted { $0.lastActivity > $1.lastActivity }
    }

    nonisolated static func completedSessions(
        before: [String: AISessionRecord], after: [AISessionRecord], at now: Date
    ) -> [AISessionCompletion] {
        after.compactMap { session in
            guard let old = before[session.id], old.status == .working,
                  session.status == .idle,
                  session.lastActivity >= old.lastActivity,
                  now.timeIntervalSince(session.lastActivity) < 60 else { return nil }
            return AISessionCompletion(
                id: session.id, source: session.source,
                projectName: session.projectName, completedAt: now
            )
        }
    }

    private func restoreSnapshot() {
        guard let data = try? Data(contentsOf: snapshotURL),
              let stored = try? JSONDecoder().decode([AISessionRecord].self, from: data) else { return }
        sessions = Self.reconcile(scanned: [], previous: stored, at: Date(), retention: retention)
    }

    private func persistSnapshot() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        let url = snapshotURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path
            )
        } catch {
            NSLog("AI session snapshot could not be saved: %@", error.localizedDescription)
        }
    }

    private func clearSnapshot() {
        let url = snapshotURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try Data("[]".utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path
            )
        } catch {
            NSLog("AI session snapshot could not be cleared: %@", error.localizedDescription)
        }
    }

    private func postNotification(for completion: AISessionCompletion) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "AI session finished"
            content.body = "A local \(completion.source.rawValue) session has finished."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "ai-session-\(completion.id)-\(completion.completedAt.timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
