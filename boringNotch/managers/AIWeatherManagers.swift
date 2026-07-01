//
//  AIWeatherManagers.swift
//  boringNotch
//
//  Created by Codex on 2026-06-06.
//

import AppKit
import Combine
import CoreLocation
import Defaults
import Foundation
import PDFKit
import UniformTypeIdentifiers

struct AgentFileReadError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        self.errorDescription = message
    }
}

func readAgentImportableFile(at url: URL) throws -> (content: String, byteCount: Int) {
    let byteCount = try agentFileByteCount(at: url)

    if url.pathExtension.lowercased() == "pdf" {
        guard byteCount <= 20_000_000 else {
            throw AgentFileReadError("PDF 太大，当前限制 20 MB。")
        }
        guard let document = PDFDocument(url: url) else {
            throw AgentFileReadError("无法打开 PDF。")
        }
        let pageTexts = (0..<document.pageCount).compactMap { index in
            document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let text = pageTexts.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentFileReadError("PDF 没有可抽取文本，当前不做 OCR。")
        }
        return ("[PDF text extracted]\n\(String(text.prefix(24_000)))", byteCount)
    }

    let data = try Data(contentsOf: url)
    guard data.count <= 512_000 else {
        throw AgentFileReadError("文件太大，当前限制 500 KB。")
    }

    guard let text = String(data: data, encoding: .utf8)
        ?? String(data: data, encoding: .unicode)
        ?? String(data: data, encoding: .utf16)
    else {
        throw AgentFileReadError("不是可读取的文本文件。")
    }

    return (String(text.prefix(16_000)), data.count)
}

func agentAllowedImportTypes() -> [UTType] {
    let extraTextTypes = [
        "md", "markdown", "swift", "py", "js", "ts", "tsx", "jsx",
        "html", "css", "xml", "yaml", "yml", "java", "c", "cpp", "h"
    ].compactMap { UTType(filenameExtension: $0) }
    return [.plainText, .utf8PlainText, .text, .json, .commaSeparatedText, .pdf] + extraTextTypes
}

private func agentFileByteCount(at url: URL) throws -> Int {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    if let fileSize = values.fileSize {
        return fileSize
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return attributes[.size] as? Int ?? 0
}

struct AIChatMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct AgentChatConversation: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [AIChatMessage]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [AIChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

struct AgentKnowledgeDocument: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var sourcePath: String
    var summary: String
    var content: String
    var keywords: [String]
    var byteCount: Int
    var createdAt: Date
    var updatedAt: Date
}

struct AgentKnowledgeSearchHit: Identifiable, Equatable {
    let id: UUID
    let document: AgentKnowledgeDocument
    let score: Double
    let reason: String
}

struct AgentPluginDescriptor: Identifiable, Equatable {
    let id: String
    let name: String
    let typeTags: [String]
    let summary: String
    let toolNames: [String]
    let permission: String
    let riskLevel: String
    let discoveryKeywords: [String]
    let manifestPreview: String

    var category: String {
        typeTags.joined(separator: "/")
    }
}

struct AgentSkillDescriptor: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let category: String
    let source: String
    let requiredTools: [String]
    let riskLevel: String
    let triggerKeywords: [String]
    let workflowSteps: [String]
    let frontMatterPreview: String

    init(
        id: String,
        name: String,
        summary: String,
        category: String = "桌面",
        source: String = "built-in",
        requiredTools: [String],
        riskLevel: String,
        triggerKeywords: [String],
        workflowSteps: [String],
        frontMatterPreview: String
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.category = category
        self.source = source
        self.requiredTools = requiredTools
        self.riskLevel = riskLevel
        self.triggerKeywords = triggerKeywords
        self.workflowSteps = workflowSteps
        self.frontMatterPreview = frontMatterPreview
    }
}

struct AgentPluginMatch: Identifiable, Equatable {
    let id: String
    let pluginName: String
    let score: Double
    let reason: String
    let selected: Bool
}

struct AgentTaskUnderstanding: Equatable {
    let taskType: String
    let complexity: String
    let riskLevel: String
    let needsTools: Bool
    let needsMemory: Bool
    let requiresClarification: Bool
    let summary: String
    let signals: [String]

    var contextText: String {
        """
        task_type: \(taskType)
        complexity: \(complexity)
        risk_level: \(riskLevel)
        needs_tools: \(needsTools ? "yes" : "no")
        needs_memory: \(needsMemory ? "yes" : "no")
        requires_clarification: \(requiresClarification ? "yes" : "no")
        signals: \(signals.isEmpty ? "无" : signals.joined(separator: ", "))
        summary: \(summary)
        """
    }
}

struct AgentReasoningProfile: Equatable {
    let mode: String
    let loop: String
    let shouldPlan: Bool
    let maxReviewRounds: Int
    let stopCondition: String

    var contextText: String {
        """
        mode: \(mode)
        loop: \(loop)
        should_plan: \(shouldPlan ? "yes" : "no")
        max_review_rounds: \(maxReviewRounds)
        stop_condition: \(stopCondition)
        """
    }
}

struct AgentPlanStep: Identifiable, Equatable {
    let id = UUID()
    let order: Int
    let title: String
    let detail: String
    let status: String
}

struct AgentRecoveryStrategy: Identifiable, Equatable {
    let id = UUID()
    let trigger: String
    let strategy: String
    let fallback: String
    let status: String
}

struct AgentWorkingMemory: Equatable {
    let currentGoal: String
    let taskProgress: String
    let keyEntities: [String]
    let pendingQuestions: [String]

    var contextText: String {
        """
        current_goal: \(currentGoal)
        task_progress: \(taskProgress)
        key_entities: \(keyEntities.joined(separator: ", "))
        pending_questions: \(pendingQuestions.isEmpty ? "无" : pendingQuestions.joined(separator: "；"))
        """
    }
}

struct AgentMemoryRecord: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case fact
        case episodic
        case procedural

        var displayName: String {
            switch self {
            case .fact:
                return "事实记忆"
            case .episodic:
                return "情景记忆"
            case .procedural:
                return "程序记忆"
            }
        }
    }

    let id: UUID
    var kind: Kind
    var content: String
    var keywords: [String]
    var createdAt: Date
    var updatedAt: Date
    var source: String
    var importance: Double
    var confidence: Double
    var accessCount: Int
    var lastAccessedAt: Date?
    var retrievalScore: Double?
    var retrievalReason: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        content: String,
        keywords: [String],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        source: String,
        importance: Double = 0.55,
        confidence: Double = 0.82,
        accessCount: Int = 0,
        lastAccessedAt: Date? = nil,
        retrievalScore: Double? = nil,
        retrievalReason: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.keywords = keywords
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
        self.importance = importance
        self.confidence = confidence
        self.accessCount = accessCount
        self.lastAccessedAt = lastAccessedAt
        self.retrievalScore = retrievalScore
        self.retrievalReason = retrievalReason
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case content
        case keywords
        case createdAt
        case updatedAt
        case source
        case importance
        case confidence
        case accessCount
        case lastAccessedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .fact
        content = try container.decode(String.self, forKey: .content)
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "legacy"
        importance = try container.decodeIfPresent(Double.self, forKey: .importance) ?? 0.55
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.82
        accessCount = try container.decodeIfPresent(Int.self, forKey: .accessCount) ?? 0
        lastAccessedAt = try container.decodeIfPresent(Date.self, forKey: .lastAccessedAt)
        retrievalScore = nil
        retrievalReason = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(content, forKey: .content)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(source, forKey: .source)
        try container.encode(importance, forKey: .importance)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(accessCount, forKey: .accessCount)
        try container.encodeIfPresent(lastAccessedAt, forKey: .lastAccessedAt)
    }
}

struct AgentTraceStep: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
    let status: String
}

struct AgentRunTrace: Identifiable, Equatable {
    let id = UUID()
    var routeKind: String
    var routeName: String
    var routeConfidence: Double
    var taskUnderstanding: AgentTaskUnderstanding
    var reasoningProfile: AgentReasoningProfile
    var discoveredPlugins: [AgentPluginMatch]
    var selectedPlugins: [AgentPluginDescriptor]
    var selectedSkills: [AgentSkillDescriptor]
    var planSteps: [AgentPlanStep]
    var workingMemory: AgentWorkingMemory?
    var retrievedMemories: [AgentMemoryRecord]
    var storedMemory: AgentMemoryRecord?
    var recoveryStrategies: [AgentRecoveryStrategy]
    var steps: [AgentTraceStep]
    var safetyNotes: [String]
    var status: String
    var requiresConfirmation: Bool

    var selectedToolNames: [String] {
        selectedPlugins.flatMap(\.toolNames)
    }
}

private struct AgentPreparedRun {
    var trace: AgentRunTrace
    let systemContext: String
    let calendarContext: String?
    let route: AgentRoute
}

private struct AgentRoute {
    enum Kind: String {
        case generalChat = "general_chat"
        case schedulePlanning = "schedule_planning"
        case calendarWrite = "calendar_write"
        case weatherDecision = "weather_decision"
        case focusCoaching = "focus_coaching"
        case assignmentPlanning = "assignment_planning"
        case agentArchitecture = "agent_architecture"
        case fileProcessing = "file_processing"
        case researchPlanning = "research_planning"
    }

    let kind: Kind
    let confidence: Double
}

@MainActor
private final class AgentMemoryStore {
    static let shared = AgentMemoryStore()

    private(set) var records: [AgentMemoryRecord] = []
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let semanticKeywords = [
        "日历", "日程", "会议", "空闲", "天气", "户外", "跑步", "学习", "复习", "作业", "大作业",
        "评分", "提交", "番茄钟", "专注", "偏好", "习惯", "周末", "晚上", "早上", "课程", "论文",
        "记忆", "长期记忆", "工作记忆", "短期记忆", "智能体", "插件", "技能", "架构", "文件",
        "calendar", "schedule", "weather", "assignment", "homework", "study", "focus", "pomodoro",
        "preference", "habit", "deadline", "paper", "memory", "agent", "plugin", "skill", "file"
    ]

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? temporaryDirectory
        let directory = baseDirectory
            .appendingPathComponent("DanShenAgent", isDirectory: true)
        fileURL = directory.appendingPathComponent("memories.json")

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        migrateLegacyMemoryIfNeeded(from: baseDirectory)
        load()
    }

    var recentRecords: [AgentMemoryRecord] {
        Array(records.sorted { $0.updatedAt > $1.updatedAt }.prefix(20))
    }

    var storageURL: URL {
        fileURL
    }

    private func migrateLegacyMemoryIfNeeded(from baseDirectory: URL) {
        let legacyDirectoryName = "Nook" + "XAgent"
        let legacyURL = baseDirectory
            .appendingPathComponent(legacyDirectoryName, isDirectory: true)
            .appendingPathComponent("memories.json")
        let previousDirectoryName = "Notch" + "MindAgent"
        let previousURL = baseDirectory
            .appendingPathComponent(previousDirectoryName, isDirectory: true)
            .appendingPathComponent("memories.json")

        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        if fileManager.fileExists(atPath: previousURL.path) {
            try? fileManager.copyItem(at: previousURL, to: fileURL)
        } else if fileManager.fileExists(atPath: legacyURL.path) {
            try? fileManager.copyItem(at: legacyURL, to: fileURL)
        }
    }

    func retrieve(prompt: String, route: AgentRoute, limit: Int = 5) -> [AgentMemoryRecord] {
        let queryKeywords = keywords(for: prompt + " " + route.kind.rawValue)
        guard !records.isEmpty, !queryKeywords.isEmpty else { return [] }

        let now = Date()
        let matches = records
            .enumerated()
            .map { index, record -> (index: Int, score: Double, reason: String) in
                let recordKeywords = Set(record.keywords)
                let matchedKeywords = Array(queryKeywords.intersection(recordKeywords)).sorted()
                let overlap = matchedKeywords.count
                let semanticScore = Double(overlap) / Double(max(queryKeywords.count, 1))
                let contentScore = queryKeywords.reduce(0.0) { partial, keyword in
                    record.content.lowercased().contains(keyword.lowercased()) ? partial + 0.05 : partial
                }
                let ageDays = max(0, now.timeIntervalSince(record.updatedAt) / 86_400)
                let recencyScore = max(0, 0.18 - min(ageDays, 30) * 0.006)
                let typeBoost = record.kind == .fact ? 0.08 : 0.03
                let importanceBoost = min(record.importance, 1.0) * 0.07
                let confidenceBoost = min(record.confidence, 1.0) * 0.04
                let score = semanticScore
                    + min(contentScore, 0.2)
                    + recencyScore
                    + typeBoost
                    + importanceBoost
                    + confidenceBoost
                let reason = retrievalReason(
                    matchedKeywords: matchedKeywords,
                    contentScore: contentScore,
                    recencyScore: recencyScore,
                    kind: record.kind
                )
                return (index, score, reason)
            }
            .filter { $0.score > 0.08 }
            .sorted { $0.score > $1.score }
            .prefix(limit)

        guard !matches.isEmpty else { return [] }

        for match in matches {
            records[match.index].accessCount += 1
            records[match.index].lastAccessedAt = now
        }
        save()

        return matches.map { match in
            var record = records[match.index]
            record.retrievalScore = match.score
            record.retrievalReason = match.reason
            return record
        }
    }

    func storeIfUseful(prompt: String, route: AgentRoute) -> AgentMemoryRecord? {
        guard shouldPersist(prompt) else { return nil }

        let content = normalizedMemoryContent(from: prompt)
        return store(content: content, routeKind: route.kind.rawValue, source: "explicit-user-message")
    }

    func storeManual(_ content: String) -> AgentMemoryRecord? {
        store(content: content, routeKind: "manual_memory", source: "slash-remember")
    }

    func forget(matching query: String) -> Int {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            let count = records.count
            clear()
            return count
        }

        let queryKeywords = keywords(for: normalizedQuery)
        let beforeCount = records.count
        records.removeAll { record in
            record.content.localizedCaseInsensitiveContains(normalizedQuery)
                || Set(record.keywords).intersection(queryKeywords).count >= 2
        }
        let removedCount = beforeCount - records.count
        if removedCount > 0 {
            save()
        }
        return removedCount
    }

    private func store(content rawContent: String, routeKind: String, source: String) -> AgentMemoryRecord? {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = AgentMemoryRecord(
            id: UUID(),
            kind: memoryKind(for: content, routeKind: routeKind),
            content: String(content.prefix(320)),
            keywords: Array(keywords(for: content + " " + routeKind)).sorted(),
            createdAt: Date(),
            updatedAt: Date(),
            source: source,
            importance: importance(for: content, source: source),
            confidence: confidence(for: source)
        )
        guard !record.content.isEmpty else { return nil }

        if let existingIndex = records.firstIndex(where: { existing in
            Set(existing.keywords).intersection(record.keywords).count >= 2
                && existing.content.localizedCaseInsensitiveContains(String(record.content.prefix(24)))
        }) {
            records[existingIndex].content = record.content
            records[existingIndex].keywords = record.keywords
            records[existingIndex].kind = record.kind
            records[existingIndex].source = record.source
            records[existingIndex].importance = max(records[existingIndex].importance, record.importance)
            records[existingIndex].confidence = max(records[existingIndex].confidence, record.confidence)
            records[existingIndex].updatedAt = Date()
            save()
            return records[existingIndex]
        }

        records.append(record)
        records = Array(records.sorted { $0.updatedAt > $1.updatedAt }.prefix(100))
        save()
        return record
    }

    func clear() {
        records.removeAll()
        save()
    }

    func keywords(for text: String) -> Set<String> {
        let lowered = text.lowercased()
        var result = Set(
            lowered
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 2 && $0.count <= 28 }
        )

        for keyword in semanticKeywords where lowered.contains(keyword.lowercased()) {
            result.insert(keyword.lowercased())
        }

        return result
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        records = (try? decoder.decode([AgentMemoryRecord].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func shouldPersist(_ prompt: String) -> Bool {
        let lowered = prompt.lowercased()
        let explicitSignals = [
            "记住", "记一下", "请记", "以后", "我的偏好", "我的习惯", "我喜欢", "我不喜欢",
            "默认", "remember", "my preference", "i prefer", "always", "never"
        ]
        return explicitSignals.contains(where: lowered.contains)
    }

    private func normalizedMemoryContent(from prompt: String) -> String {
        let withoutFiles = prompt
            .components(separatedBy: "本地文件上下文：")
            .first ?? prompt
        return withoutFiles
            .replacingOccurrences(of: "请记住", with: "")
            .replacingOccurrences(of: "记住", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func memoryKind(for content: String, routeKind: String) -> AgentMemoryRecord.Kind {
        let lowered = content.lowercased()
        if lowered.contains("流程") || lowered.contains("步骤") || lowered.contains("workflow") {
            return .procedural
        }
        if routeKind == AgentRoute.Kind.assignmentPlanning.rawValue
            || lowered.contains("上次")
            || lowered.contains("过去")
        {
            return .episodic
        }
        return .fact
    }

    private func importance(for content: String, source: String) -> Double {
        let lowered = content.lowercased()
        var score = source == "slash-remember" ? 0.72 : 0.58
        if ["默认", "偏好", "习惯", "喜欢", "不喜欢", "always", "never", "prefer"].contains(where: lowered.contains) {
            score += 0.2
        }
        if ["流程", "步骤", "workflow", "以后"].contains(where: lowered.contains) {
            score += 0.12
        }
        return min(score, 1.0)
    }

    private func confidence(for source: String) -> Double {
        source == "slash-remember" ? 0.96 : 0.9
    }

    private func retrievalReason(
        matchedKeywords: [String],
        contentScore: Double,
        recencyScore: Double,
        kind: AgentMemoryRecord.Kind
    ) -> String {
        var reasons: [String] = []
        if !matchedKeywords.isEmpty {
            reasons.append("关键词 \(matchedKeywords.prefix(4).joined(separator: ", "))")
        }
        if contentScore > 0 {
            reasons.append("内容命中")
        }
        if recencyScore > 0.12 {
            reasons.append("近期更新")
        }
        if kind == .fact {
            reasons.append("稳定事实")
        }
        return reasons.isEmpty ? "低权重相关" : reasons.joined(separator: " + ")
    }
}

@MainActor
private final class AgentKnowledgeStore {
    static let shared = AgentKnowledgeStore()

    private(set) var documents: [AgentKnowledgeDocument] = []
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let semanticKeywords = [
        "知识库", "资料库", "课程", "作业", "评分", "提交", "论文", "文献", "报告", "计划",
        "插件", "技能", "智能体", "记忆", "天气", "日程", "番茄钟", "knowledge", "rag",
        "assignment", "rubric", "paper", "research", "agent", "plugin", "skill", "memory"
    ]

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let directory = Self.storageDirectory()
        fileURL = directory.appendingPathComponent("knowledge.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    var storageURL: URL {
        fileURL
    }

    @discardableResult
    func addDocument(
        title rawTitle: String,
        sourcePath: String,
        content rawContent: String,
        byteCount: Int
    ) -> AgentKnowledgeDocument? {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "未命名资料"
            : rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let summary = summarize(content)
        let keywords = Array(keywords(for: "\(title) \(summary) \(content.prefix(2400))")).sorted()

        if let index = documents.firstIndex(where: { $0.sourcePath == sourcePath }) {
            documents[index].title = title
            documents[index].summary = summary
            documents[index].content = String(content.prefix(32_000))
            documents[index].keywords = keywords
            documents[index].byteCount = byteCount
            documents[index].updatedAt = now
            save()
            return documents[index]
        }

        let document = AgentKnowledgeDocument(
            id: UUID(),
            title: title,
            sourcePath: sourcePath,
            summary: summary,
            content: String(content.prefix(32_000)),
            keywords: keywords,
            byteCount: byteCount,
            createdAt: now,
            updatedAt: now
        )
        documents.insert(document, at: 0)
        documents = Array(documents.sorted { $0.updatedAt > $1.updatedAt }.prefix(80))
        save()
        return document
    }

    func retrieve(query: String, limit: Int = 3) -> [AgentKnowledgeSearchHit] {
        let queryKeywords = keywords(for: query)
        let lowered = query.lowercased()
        guard !documents.isEmpty else { return [] }

        return documents.compactMap { document in
            let documentKeywords = Set(document.keywords)
            let matched = documentKeywords.intersection(queryKeywords)
            let titleHit = document.title.lowercased().contains(lowered) && lowered.count >= 2
            let contentHit = document.content.lowercased().contains(lowered) && lowered.count >= 3
            let age = max(0, Date().timeIntervalSince(document.updatedAt))
            let recency = max(0.0, 0.12 - min(age / 604_800, 1.0) * 0.12)
            let score = min(Double(matched.count) * 0.18 + (titleHit ? 0.24 : 0) + (contentHit ? 0.16 : 0) + recency, 1.0)
            guard score >= 0.18 else { return nil }

            let reason = matched.isEmpty
                ? "标题/正文命中"
                : "关键词 \(matched.prefix(5).joined(separator: ", "))"
            return AgentKnowledgeSearchHit(
                id: document.id,
                document: document,
                score: score,
                reason: reason
            )
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map { $0 }
    }

    func hasRelevantContent(for query: String) -> Bool {
        !retrieve(query: query, limit: 1).isEmpty
    }

    func removeDocument(id: UUID) {
        documents.removeAll { $0.id == id }
        save()
    }

    func clear() {
        documents.removeAll()
        save()
    }

    private static func storageDirectory() -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? temporaryDirectory
        return baseDirectory.appendingPathComponent("DanShenAgent", isDirectory: true)
    }

    private func summarize(_ content: String) -> String {
        let cleanedLines = content
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let seed = cleanedLines.prefix(3).joined(separator: " ")
        return String(seed.prefix(220))
    }

    private func keywords(for text: String) -> Set<String> {
        let lowered = text.lowercased()
        var result = Set(
            lowered
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 2 && $0.count <= 28 }
        )

        for keyword in semanticKeywords where lowered.contains(keyword.lowercased()) {
            result.insert(keyword.lowercased())
        }
        return result
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        documents = (try? decoder.decode([AgentKnowledgeDocument].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? encoder.encode(documents) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

@MainActor
private final class AgentOrchestrator {
    static let shared = AgentOrchestrator()
    private static let weatherCalendarKeywords = [
        "schedule", "calendar", "available", "outdoor", "run",
        "安排", "计划", "日程", "行程", "空闲", "会议", "户外", "跑步", "出门", "运动"
    ]

    let plugins: [AgentPluginDescriptor] = [
        .init(
            id: "calendar",
            name: "日程管理",
            typeTags: ["context", "action"],
            summary: "读取近期日程，并在明确要求时创建日历计划。",
            toolNames: ["calendar.read", "calendar.create_event"],
            permission: "读取自动，写入受设置控制",
            riskLevel: "中",
            discoveryKeywords: ["calendar", "schedule", "agenda", "日程", "行程", "会议", "空闲", "写入日历"],
            manifestPreview: """
            {"id":"calendar","type":["context","action"],"tools":["calendar.read","calendar.create_event"],"permissions":{"read":"auto","write":"settings-gated"},"riskLevel":"medium"}
            """
        ),
        .init(
            id: "weather",
            name: "天气查询",
            typeTags: ["context"],
            summary: "获取 Open-Meteo 当前天气，用于出行和户外决策。",
            toolNames: ["weather.current", "weather.hourly"],
            permission: "读取自动",
            riskLevel: "低",
            discoveryKeywords: ["weather", "rain", "temperature", "outdoor", "天气", "下雨", "气温", "户外", "跑步"],
            manifestPreview: """
            {"id":"weather","type":["context"],"tools":["weather.current","weather.hourly"],"permissions":{"read":"auto"},"riskLevel":"low"}
            """
        ),
        .init(
            id: "focus",
            name: "焦点计时",
            typeTags: ["context", "action"],
            summary: "读取番茄钟状态和专注时长偏好。",
            toolNames: ["focus.status", "focus.start"],
            permission: "读取自动，动作由用户触发",
            riskLevel: "低",
            discoveryKeywords: ["focus", "pomodoro", "study", "deep work", "专注", "番茄钟", "学习", "冲刺"],
            manifestPreview: """
            {"id":"focus","type":["context","action"],"tools":["focus.status","focus.start"],"permissions":{"read":"auto","action":"user-triggered"},"riskLevel":"low"}
            """
        ),
        .init(
            id: "skills",
            name: "技能手册",
            typeTags: ["skill"],
            summary: "注入类似 Codex/Claude Skills 的任务流程。",
            toolNames: ["skill.study_plan", "skill.assignment_breakdown"],
            permission: "读取自动",
            riskLevel: "低",
            discoveryKeywords: ["skill", "study plan", "assignment", "复习", "作业", "拆解", "规划"],
            manifestPreview: """
            {"id":"skills","type":["skill"],"tools":["skill.study_plan","skill.assignment_breakdown"],"permissions":{"read":"auto"},"riskLevel":"low"}
            """
        ),
        .init(
            id: "assignment",
            name: "作业资料",
            typeTags: ["context", "skill"],
            summary: "识别上传或本地文本中的作业要求，提取评分点和交付物。",
            toolNames: ["assignment.extract_requirements", "assignment.rubric_map"],
            permission: "读取用户显式提供的文件",
            riskLevel: "低",
            discoveryKeywords: ["assignment", "homework", "rubric", "作业", "大作业", "评分", "要求", "提交"],
            manifestPreview: """
            {"id":"assignment","type":["context","skill"],"tools":["assignment.extract_requirements","assignment.rubric_map"],"permissions":{"read":"provided-files-only"},"riskLevel":"low"}
            """
        ),
        .init(
            id: "shelf",
            name: "文件架",
            typeTags: ["context"],
            summary: "面向拖入 Notch 的文件做摘要、归类和待办提取。",
            toolNames: ["shelf.summarize", "shelf.extract_todos"],
            permission: "读取用户拖入或上传的文件",
            riskLevel: "低",
            discoveryKeywords: ["file", "shelf", "summary", "todo", "文件", "上传", "摘要", "待办"],
            manifestPreview: """
            {"id":"shelf","type":["context"],"tools":["shelf.summarize","shelf.extract_todos"],"permissions":{"read":"provided-files-only"},"riskLevel":"low"}
            """
        ),
        .init(
            id: "memory",
            name: "偏好记忆",
            typeTags: ["context", "action"],
            summary: "管理短期会话、工作记忆和本地长期记忆检索。",
            toolNames: ["memory.short_term", "memory.working_state", "memory.retrieve", "memory.save_preference"],
            permission: "读取自动，长期写入只在用户明确要求记住时发生",
            riskLevel: "低",
            discoveryKeywords: ["preference", "habit", "memory", "remember", "偏好", "习惯", "记住", "长期记忆", "工作记忆"],
            manifestPreview: """
            {"id":"memory","type":["context","action"],"tools":["memory.short_term","memory.working_state","memory.retrieve","memory.save_preference"],"permissions":{"read":"auto","write":"explicit-memory-request"},"riskLevel":"low"}
            """
        ),
        .init(
            id: "knowledge",
            name: "本地知识库",
            typeTags: ["context"],
            summary: "检索用户导入的study materials、作业要求、论文笔记和 Markdown 文档。",
            toolNames: ["knowledge.add_document", "knowledge.retrieve"],
            permission: "只读取用户显式导入的文件",
            riskLevel: "低",
            discoveryKeywords: ["knowledge", "rag", "notes", "document", "知识库", "资料库", "study materials", "笔记", "文档"],
            manifestPreview: """
            {"id":"knowledge","type":["context"],"tools":["knowledge.add_document","knowledge.retrieve"],"permissions":{"read":"user-imported-only","write":"explicit-import"},"riskLevel":"low"}
            """
        ),
        .init(
            id: "planner",
            name: "任务规划器",
            typeTags: ["cognition"],
            summary: "把复杂目标拆成有顺序、可检查的执行步骤。",
            toolNames: ["planner.decompose", "planner.dependency_map"],
            permission: "始终启用，只生成计划",
            riskLevel: "低",
            discoveryKeywords: ["plan", "planner", "decompose", "规划", "计划", "拆解", "步骤", "里程碑"],
            manifestPreview: """
            {"id":"planner","type":["cognition"],"tools":["planner.decompose","planner.dependency_map"],"permissions":{"read":"always-on","write":"never"},"riskLevel":"low"}
            """
        ),
        .init(
            id: "reasoner",
            name: "推理模式选择",
            typeTags: ["cognition"],
            summary: "根据任务复杂度选择直接回答、工作流、ReAct 或自我修正模式。",
            toolNames: ["reasoner.mode_select", "reasoner.react_loop", "reasoner.self_correction"],
            permission: "始终启用，只控制思考流程",
            riskLevel: "低",
            discoveryKeywords: ["reason", "react", "cot", "推理", "思考", "自我修正", "复杂任务"],
            manifestPreview: """
            {"id":"reasoner","type":["cognition"],"tools":["reasoner.mode_select","reasoner.react_loop","reasoner.self_correction"],"permissions":{"read":"always-on","write":"never"},"riskLevel":"low"}
            """
        ),
        .init(
            id: "reviewer",
            name: "反思评审器",
            typeTags: ["guard", "cognition"],
            summary: "从输出、过程和策略三个层面检查回答质量。",
            toolNames: ["review.output_check", "review.process_check", "review.strategy_check"],
            permission: "始终启用，只做质量检查",
            riskLevel: "低",
            discoveryKeywords: ["review", "reflect", "quality", "反思", "检查", "评审", "质量"],
            manifestPreview: """
            {"id":"reviewer","type":["guard","cognition"],"tools":["review.output_check","review.process_check","review.strategy_check"],"permissions":{"read":"always-on","write":"never"},"riskLevel":"low"}
            """
        ),
        .init(
            id: "recovery",
            name: "异常恢复器",
            typeTags: ["guard"],
            summary: "为工具失败、缺失信息、格式错误和权限不足提供降级策略。",
            toolNames: ["recovery.retry", "recovery.degrade", "recovery.ask_user"],
            permission: "始终启用，不自动执行危险动作",
            riskLevel: "低",
            discoveryKeywords: ["recovery", "fallback", "error", "失败", "异常", "降级", "恢复", "重试"],
            manifestPreview: """
            {"id":"recovery","type":["guard"],"tools":["recovery.retry","recovery.degrade","recovery.ask_user"],"permissions":{"read":"always-on","write":"never"},"riskLevel":"low"}
            """
        ),
        .init(
            id: "safety",
            name: "安全护栏",
            typeTags: ["guard"],
            summary: "检查风险动作、缺失信息和工具失败。",
            toolNames: ["guard.risk_check", "guard.reflection"],
            permission: "始终启用",
            riskLevel: "低",
            discoveryKeywords: ["risk", "confirm", "safe", "权限", "确认", "安全", "护栏"],
            manifestPreview: """
            {"id":"safety","type":["guard"],"tools":["guard.risk_check","guard.reflection"],"permissions":{"read":"always-on","write":"never"},"riskLevel":"low"}
            """
        ),
        .init(
            id: "trace",
            name: "执行轨迹",
            typeTags: ["guard", "context"],
            summary: "记录路由、插件发现、工具上下文、安全检查和执行结果。",
            toolNames: ["trace.log", "trace.explain"],
            permission: "始终启用",
            riskLevel: "低",
            discoveryKeywords: ["trace", "explain", "debug", "轨迹", "解释", "调试"],
            manifestPreview: """
            {"id":"trace","type":["guard","context"],"tools":["trace.log","trace.explain"],"permissions":{"read":"always-on"},"riskLevel":"low"}
            """
        ),
    ]

    let skills: [AgentSkillDescriptor] = [
        .init(
            id: "study_plan",
            name: "学习计划",
            summary: "把复习、阅读、作业拆成可执行的专注块。",
            category: "学习",
            requiredTools: ["calendar.read", "focus.status", "memory.preferences"],
            riskLevel: "低",
            triggerKeywords: ["study", "review", "exam", "学习", "复习", "考试"],
            workflowSteps: ["读取日程空档", "拆分知识点和任务块", "映射番茄钟节奏", "输出当天/本周计划"],
            frontMatterPreview: """
            ---
            name: study-plan
            required_tools: calendar.read, focus.status, memory.preferences
            risk: low
            ---
            """
        ),
        .init(
            id: "assignment_breakdown",
            name: "作业拆解",
            summary: "按评分标准拆交付物、里程碑和当天任务。",
            category: "学习",
            requiredTools: ["calendar.read", "focus.status", "skill.assignment_breakdown"],
            riskLevel: "低",
            triggerKeywords: ["assignment", "homework", "rubric", "作业", "大作业", "评分"],
            workflowSteps: ["提取作业要求", "列出评分点", "拆成里程碑", "安排可执行任务", "标出缺失信息"],
            frontMatterPreview: """
            ---
            name: assignment-breakdown
            required_tools: assignment.extract_requirements, calendar.read, focus.status
            risk: low
            ---
            """
        ),
        .init(
            id: "calendar_aware_planning",
            name: "日程感知规划",
            summary: "读取空闲时间，避免冲突，输出绝对时间安排。",
            category: "桌面",
            requiredTools: ["calendar.read", "calendar.create_event"],
            riskLevel: "中",
            triggerKeywords: ["calendar", "schedule", "meeting", "日历", "日程", "会议", "空闲", "行程"],
            workflowSteps: ["读取近期日程", "找空闲窗口", "规避冲突", "给出绝对时间", "写入前确认边界"],
            frontMatterPreview: """
            ---
            name: calendar-aware-planning
            required_tools: calendar.read, calendar.create_event
            risk: requires-confirmation
            ---
            """
        ),
        .init(
            id: "weather_decision",
            name: "天气决策",
            summary: "结合天气、时间和日程给出出行/运动建议。",
            category: "桌面",
            requiredTools: ["weather.current"],
            riskLevel: "低",
            triggerKeywords: ["weather", "outdoor", "run", "天气", "户外", "跑步", "出门"],
            workflowSteps: ["读取当前天气", "判断天气风险", "给出穿衣/出行建议", "必要时提示缺失信息"],
            frontMatterPreview: """
            ---
            name: weather-decision
            required_tools: weather.current
            risk: low
            ---
            """
        ),
        .init(
            id: "agent_memory_design",
            name: "智能体记忆设计",
            summary: "把短期记忆、工作记忆、长期记忆和 Token 管理组织成可解释架构。",
            category: "智能体",
            requiredTools: ["memory.short_term", "memory.working_state", "memory.retrieve", "planner.decompose"],
            riskLevel: "低",
            triggerKeywords: ["memory", "agent", "plugin", "skill", "记忆", "智能体", "插件", "架构"],
            workflowSteps: ["区分三层记忆", "定义写入策略", "设计混合检索", "控制上下文注入", "暴露 trace 解释"],
            frontMatterPreview: """
            ---
            name: agent-memory-design
            required_tools: memory.short_term, memory.working_state, memory.retrieve
            risk: low
            ---
            """
        ),
        .init(
            id: "file_context_analysis",
            name: "文件上下文分析",
            summary: "读取用户显式上传文本，提取摘要、任务、风险和下一步。",
            category: "文件",
            requiredTools: ["shelf.summarize", "shelf.extract_todos"],
            riskLevel: "低",
            triggerKeywords: ["file", "upload", "文件", "上传", "摘要", "读取"],
            workflowSteps: ["确认文件来源", "摘要核心内容", "提取待办和实体", "标出缺失信息", "只引用已提供上下文"],
            frontMatterPreview: """
            ---
            name: file-context-analysis
            required_tools: shelf.summarize, shelf.extract_todos
            risk: low
            ---
            """
        ),
        .init(
            id: "research_planning",
            name: "研究规划",
            summary: "把论文、调研或报告主题拆成检索问题、证据表和产出计划。",
            category: "学术",
            requiredTools: ["planner.decompose", "memory.retrieve"],
            riskLevel: "低",
            triggerKeywords: ["research", "paper", "literature", "论文", "文献", "调研", "研究"],
            workflowSteps: ["界定研究问题", "拆分检索方向", "规划证据表", "安排写作里程碑", "说明需要外部资料"],
            frontMatterPreview: """
            ---
            name: research-planning
            required_tools: planner.decompose, memory.retrieve
            risk: low
            ---
            """
        ),
        .init(
            id: "nature_academic_search",
            name: "Nature 文献检索",
            summary: "参考本地 nature-academic-search，把多源文献检索、候选筛选和引用导出拆成流程。",
            category: "学术",
            source: "local-codex-nature",
            requiredTools: ["planner.decompose", "memory.retrieve", "external.literature_search"],
            riskLevel: "低",
            triggerKeywords: ["literature", "search", "pubmed", "crossref", "arxiv", "文献", "检索", "调研", "综述"],
            workflowSteps: ["定义检索问题", "拆英文关键词和同义词", "区分 PubMed/CrossRef/arXiv 场景", "建立候选证据表", "标注可信度和缺口"],
            frontMatterPreview: """
            ---
            name: nature-academic-search
            required_tools: planner.decompose, external.literature_search
            source: local-codex-skill-summary
            risk: low
            ---
            """
        ),
        .init(
            id: "nature_reader",
            name: "Nature 论文精读",
            summary: "参考本地 nature-reader，把论文转成中英对照、图表贴近原文、可追溯的阅读稿。",
            category: "学术",
            source: "local-codex-nature",
            requiredTools: ["shelf.summarize", "memory.retrieve"],
            riskLevel: "低",
            triggerKeywords: ["reader", "pdf", "translate paper", "全文翻译", "中英文", "原文对照", "精读", "读论文", "解读论文"],
            workflowSteps: ["确认论文来源", "保留章节结构", "中英段落对照", "图表靠近首次解释处", "输出 source anchors 和阅读备注"],
            frontMatterPreview: """
            ---
            name: nature-reader
            required_tools: shelf.summarize, memory.retrieve
            source: local-codex-skill-summary
            risk: low
            ---
            """
        ),
        .init(
            id: "nature_writing",
            name: "Nature 科学写作",
            summary: "参考本地 nature-writing，从证据、贡献和论证顺序重建摘要、引言、结果或讨论。",
            category: "学术",
            source: "local-codex-nature",
            requiredTools: ["planner.decompose", "memory.retrieve"],
            riskLevel: "低",
            triggerKeywords: ["manuscript", "abstract", "introduction", "discussion", "写作", "论文摘要", "写摘要", "摘要写作", "引言", "结果", "讨论", "改写论文"],
            workflowSteps: ["先列作者证据", "搭建论证骨架", "控制创新性和边界", "按章节写作", "标出缺失证据和占位"],
            frontMatterPreview: """
            ---
            name: nature-writing
            required_tools: planner.decompose, memory.retrieve
            source: local-codex-skill-summary
            risk: low
            ---
            """
        ),
        .init(
            id: "nature_citation",
            name: "Nature 严格引用",
            summary: "参考本地 nature-citation，把文本切分成可引用片段，并保守匹配 Nature/CNS/Cell 等支撑文献。",
            category: "学术",
            source: "local-codex-nature",
            requiredTools: ["planner.decompose", "external.literature_search"],
            riskLevel: "低",
            triggerKeywords: ["citation", "reference", "cns", "nature", "cell", "引用", "参考文献", "支撑文献", "补引用", "分段引用"],
            workflowSteps: ["切分待支撑句子", "翻译成英文检索 claim", "查找候选文献", "判断强/部分/背景支撑", "输出引用建议和风险"],
            frontMatterPreview: """
            ---
            name: nature-citation
            required_tools: external.literature_search
            source: local-codex-skill-summary
            risk: low
            ---
            """
        ),
    ]

    private init() {}

    func prepare(prompt: String, recentMessages: [AIChatMessage] = []) async -> AgentPreparedRun {
        let route = routePrompt(prompt)
        let discoveredPlugins = discoverPlugins(for: route, prompt: prompt)
        let selectedPlugins = discoveredPlugins
            .filter(\.selected)
            .compactMap { match in plugins.first(where: { $0.id == match.id }) }
        let selectedSkills = skillsForRoute(route, prompt: prompt)
        let taskUnderstanding = buildTaskUnderstanding(
            prompt: prompt,
            route: route,
            selectedPlugins: selectedPlugins,
            selectedSkills: selectedSkills
        )
        let reasoningProfile = buildReasoningProfile(for: taskUnderstanding, route: route)
        let planSteps = buildPlanSteps(
            route: route,
            selectedPlugins: selectedPlugins,
            selectedSkills: selectedSkills
        )
        var workingMemory: AgentWorkingMemory?
        var retrievedMemories: [AgentMemoryRecord] = []
        var storedMemory: AgentMemoryRecord?

        var steps: [AgentTraceStep] = [
            .init(
                title: "路由",
                detail: "\(route.kind.displayName)，置信度 \(String(format: "%.2f", route.confidence))",
                status: "done"
            ),
            .init(
                title: "渐进式插件发现",
                detail: discoveredPlugins.prefix(5).map {
                    "\($0.pluginName) \(Int(($0.score * 100).rounded()))%：\($0.reason)"
                }.joined(separator: "；"),
                status: "done"
            ),
            .init(
                title: "装载插件",
                detail: selectedPlugins.map { "\($0.name)[\($0.category)]" }.joined(separator: "、"),
                status: "done"
            ),
        ]

        var contextBlocks: [String] = []
        var calendarContext: String?
        let selectedIDs = Set(selectedPlugins.map(\.id))

        if selectedIDs.contains("memory") {
            let memoryStore = AgentMemoryStore.shared
            let shortTermContext = shortTermSummary(from: recentMessages)
            workingMemory = buildWorkingMemory(
                prompt: prompt,
                route: route,
                selectedPlugins: selectedPlugins,
                selectedSkills: selectedSkills
            )
            storedMemory = memoryStore.storeIfUseful(prompt: prompt, route: route)
            retrievedMemories = memoryStore.retrieve(prompt: prompt, route: route)

            contextBlocks.append("[memory.short_term]\n\(shortTermContext)")
            if let workingMemory {
                contextBlocks.append("[memory.working_state]\n\(workingMemory.contextText)")
            }
            contextBlocks.append("[memory.preferences]\n\(preferenceSummary())")
            contextBlocks.append("[memory.long_term]\n\(longTermMemorySummary(retrievedMemories))")

            steps.append(.init(title: "短期记忆", detail: "保留最近 \(min(recentMessages.count, 6)) 条会话摘要。", status: "done"))
            if let workingMemory {
                steps.append(.init(title: "工作记忆", detail: workingMemory.currentGoal, status: "done"))
            }
            steps.append(
                .init(
                    title: "长期记忆检索",
                    detail: retrievedMemories.isEmpty ? "无相关长期记忆" : "命中 \(retrievedMemories.count) 条：\(retrievedMemories.prefix(3).map(\.content).joined(separator: "；"))",
                    status: retrievedMemories.isEmpty ? "skipped" : "done"
                )
            )
            if let storedMemory {
                steps.append(.init(title: "长期记忆写入", detail: storedMemory.content, status: "done"))
            }
        }

        if selectedIDs.contains("knowledge"), Defaults[.aiKnowledgeRetrievalEnabled] {
            let retrievalLimit = min(max(Defaults[.aiKnowledgeRetrievalLimit], 1), 8)
            let hits = AgentKnowledgeStore.shared.retrieve(query: prompt, limit: retrievalLimit)
            let knowledgeContext: String
            if hits.isEmpty {
                knowledgeContext = "知识库没有命中相关资料。"
            } else {
                knowledgeContext = hits.enumerated().map { index, hit in
                    """
                    \(index + 1). \(hit.document.title) score=\(String(format: "%.2f", hit.score)) reason=\(hit.reason)
                    source: \(hit.document.sourcePath)
                    summary: \(hit.document.summary)
                    excerpt: \(String(hit.document.content.prefix(900)))
                    """
                }.joined(separator: "\n\n")
            }
            contextBlocks.append("[knowledge.retrieve]\n\(knowledgeContext)")
            steps.append(
                .init(
                    title: "工具 knowledge.retrieve",
                    detail: hits.isEmpty ? "本地知识库无相关命中" : "命中 \(hits.count) 份资料：\(hits.map { $0.document.title }.joined(separator: "、"))",
                    status: hits.isEmpty ? "skipped" : "done"
                )
            )
        }

        if selectedIDs.contains("calendar") {
            if Defaults[.aiCalendarContextEnabled] {
                calendarContext = await CalendarManager.shared.aiScheduleContext()
                contextBlocks.append(
                    """
                    [calendar.read]
                    \(calendarContext ?? "日历上下文不可用。如果任务依赖日程，请提示用户开启日历权限。")
                    """
                )
                steps.append(
                    .init(
                        title: "工具 calendar.read",
                        detail: calendarContext == nil ? "不可用或权限不足" : "已读取近期日程",
                        status: calendarContext == nil ? "fallback" : "done"
                    )
                )
            } else {
                contextBlocks.append("[calendar.read]\nDisabled in Settings > AI.")
                steps.append(.init(title: "工具 calendar.read", detail: "用户设置已关闭", status: "skipped"))
            }
        }

        if selectedIDs.contains("assignment") {
            let hasProvidedFile = prompt.contains("[file:") || prompt.contains("本地文件上下文")
            let assignmentContext = hasProvidedFile
                ? "已检测到用户上传的作业/文本上下文；后续回复需要提取交付物、评分点和缺失信息。"
                : "未检测到上传的作业要求文件；如任务依赖评分标准，需要请用户上传或粘贴要求。"
            contextBlocks.append("[assignment.extract_requirements]\n\(assignmentContext)")
            steps.append(
                .init(
                    title: "工具 assignment.extract_requirements",
                    detail: assignmentContext,
                    status: hasProvidedFile ? "done" : "fallback"
                )
            )
        }

        if selectedIDs.contains("shelf") {
            let hasProvidedFile = prompt.contains("[file:") || prompt.contains("本地文件上下文")
            let shelfContext = hasProvidedFile
                ? "已读取本轮显式上传文件，可用于摘要、归类和待办提取。"
                : "文件架上下文仅在用户上传或拖入文件时启用。"
            contextBlocks.append("[shelf.summarize]\n\(shelfContext)")
            steps.append(
                .init(
                    title: "工具 shelf.summarize",
                    detail: shelfContext,
                    status: hasProvidedFile ? "done" : "skipped"
                )
            )
        }

        if selectedIDs.contains("weather") {
            let weatherContext = await weatherSummary()
            contextBlocks.append("[weather.current]\n\(weatherContext)")
            steps.append(.init(title: "工具 weather.current", detail: weatherContext, status: weatherContext.contains("不可用") ? "fallback" : "done"))
        }

        if selectedIDs.contains("focus") {
            let focusContext = focusSummary()
            contextBlocks.append("[focus.status]\n\(focusContext)")
            steps.append(.init(title: "工具 focus.status", detail: focusContext, status: "done"))
        }

        if selectedIDs.contains("skills") {
            let skillContext = skillPlaybook(for: route, selectedSkills: selectedSkills)
            contextBlocks.append("[skill.playbook]\n\(skillContext)")
            steps.append(
                .init(
                    title: "Skills 选择",
                    detail: selectedSkills.isEmpty ? playbookName(for: route) : selectedSkills.map(\.name).joined(separator: "、"),
                    status: "done"
                )
            )
        }

        let safetyNotes = safetyNotes(for: route, contextBlocks: contextBlocks)
        let recoveryStrategies = buildRecoveryStrategies(
            route: route,
            selectedPlugins: selectedPlugins,
            contextBlocks: contextBlocks
        )
        steps.append(
            .init(
                title: "Permission Gate",
                detail: permissionGateSummary(for: selectedPlugins, route: route),
                status: route.kind == .calendarWrite ? "prepared" : "done"
            )
        )
        steps.append(
            .init(
                title: "Reflector / Guard",
                detail: safetyNotes.joined(separator: " "),
                status: "done"
            )
        )
        if selectedIDs.contains("trace") {
            steps.append(.init(title: "Trace Logger", detail: "记录路由、工具发现、上下文和安全检查。", status: "done"))
        }

        let systemContext = buildSystemContext(
            route: route,
            taskUnderstanding: taskUnderstanding,
            reasoningProfile: reasoningProfile,
            planSteps: planSteps,
            recoveryStrategies: recoveryStrategies,
            plugins: selectedPlugins,
            skills: selectedSkills,
            contextBlocks: contextBlocks,
            safetyNotes: safetyNotes
        )

        let trace = AgentRunTrace(
            routeKind: route.kind.rawValue,
            routeName: route.kind.displayName,
            routeConfidence: route.confidence,
            taskUnderstanding: taskUnderstanding,
            reasoningProfile: reasoningProfile,
            discoveredPlugins: discoveredPlugins,
            selectedPlugins: selectedPlugins,
            selectedSkills: selectedSkills,
            planSteps: planSteps,
            workingMemory: workingMemory,
            retrievedMemories: retrievedMemories,
            storedMemory: storedMemory,
            recoveryStrategies: recoveryStrategies,
            steps: steps,
            safetyNotes: safetyNotes,
            status: "已准备",
            requiresConfirmation: route.kind == .calendarWrite
        )

        return AgentPreparedRun(
            trace: trace,
            systemContext: systemContext,
            calendarContext: calendarContext,
            route: route
        )
    }

    private func buildTaskUnderstanding(
        prompt: String,
        route: AgentRoute,
        selectedPlugins: [AgentPluginDescriptor],
        selectedSkills: [AgentSkillDescriptor]
    ) -> AgentTaskUnderstanding {
        let lowered = prompt.lowercased()
        let signals = selectedPlugins.map(\.id) + selectedSkills.map(\.id)
        let complexity: String
        if prompt.count > 420 || !selectedSkills.isEmpty || route.kind == .agentArchitecture || route.kind == .researchPlanning {
            complexity = "high"
        } else if route.kind == .generalChat {
            complexity = "low"
        } else {
            complexity = "medium"
        }

        let riskyWords = ["写入", "创建", "删除", "不用问", "直接", "always", "delete", "create"]
        let riskLevel = route.kind == .calendarWrite || riskyWords.contains(where: lowered.contains) ? "medium" : "low"
        let needsTools = route.kind != .generalChat || selectedPlugins.contains { !$0.toolNames.isEmpty }
        let needsMemory = selectedPlugins.contains { $0.id == "memory" } || lowered.contains("记忆") || lowered.contains("remember")
        let requiresClarification = pendingQuestions(for: prompt, route: route).isEmpty == false

        return AgentTaskUnderstanding(
            taskType: route.kind.displayName,
            complexity: complexity,
            riskLevel: riskLevel,
            needsTools: needsTools,
            needsMemory: needsMemory,
            requiresClarification: requiresClarification,
            summary: "\(route.kind.displayName)：\(String(prompt.replacingOccurrences(of: "\n", with: " ").prefix(120)))",
            signals: Array(signals.prefix(10))
        )
    }

    private func buildReasoningProfile(
        for understanding: AgentTaskUnderstanding,
        route: AgentRoute
    ) -> AgentReasoningProfile {
        let mode: String
        let loop: String
        let reviewRounds: Int

        switch route.kind {
        case .generalChat:
            mode = "direct"
            loop = "answer -> light_guard"
            reviewRounds = 1
        case .calendarWrite:
            mode = "permissioned_planning"
            loop = "plan -> permission_gate -> execute_or_explain -> review"
            reviewRounds = 2
        case .agentArchitecture, .researchPlanning:
            mode = "structured_workflow"
            loop = "understand -> decompose -> retrieve -> synthesize -> review"
            reviewRounds = 2
        case .fileProcessing:
            mode = "grounded_context"
            loop = "read_provided_context -> extract -> answer -> guard"
            reviewRounds = 1
        case .schedulePlanning, .weatherDecision, .focusCoaching, .assignmentPlanning:
            mode = understanding.complexity == "high" ? "react_workflow" : "tool_grounded"
            loop = "route -> collect_context -> skill_playbook -> answer -> review"
            reviewRounds = 1
        }

        return AgentReasoningProfile(
            mode: mode,
            loop: loop,
            shouldPlan: understanding.complexity != "low",
            maxReviewRounds: reviewRounds,
            stopCondition: "回答已覆盖目标、工具边界和缺失信息。"
        )
    }

    private func buildPlanSteps(
        route: AgentRoute,
        selectedPlugins: [AgentPluginDescriptor],
        selectedSkills: [AgentSkillDescriptor]
    ) -> [AgentPlanStep] {
        var steps: [AgentPlanStep] = [
            .init(order: 1, title: "理解任务", detail: "识别 \(route.kind.displayName) 并抽取关键实体。", status: "done"),
            .init(order: 2, title: "发现插件", detail: selectedPlugins.map(\.name).joined(separator: "、"), status: "done"),
        ]

        if selectedPlugins.contains(where: { $0.id == "memory" }) {
            steps.append(.init(order: steps.count + 1, title: "装载记忆", detail: "更新短期/工作记忆，并检索相关长期记忆。", status: "done"))
        }

        if !selectedSkills.isEmpty {
            steps.append(.init(order: steps.count + 1, title: "应用 Skills", detail: selectedSkills.map(\.name).joined(separator: "、"), status: "done"))
        }

        steps.append(.init(order: steps.count + 1, title: "生成与检查", detail: "按权限边界回答，并通过安全护栏检查。", status: "prepared"))
        return steps
    }

    private func buildRecoveryStrategies(
        route: AgentRoute,
        selectedPlugins: [AgentPluginDescriptor],
        contextBlocks: [String]
    ) -> [AgentRecoveryStrategy] {
        var strategies: [AgentRecoveryStrategy] = []

        if selectedPlugins.contains(where: { $0.id == "calendar" }) {
            strategies.append(
                .init(
                    trigger: "日历权限不可用",
                    strategy: "改为输出人工可复制的绝对时间计划。",
                    fallback: "提示用户在设置中开启日历读取/写入。",
                    status: contextBlocks.contains(where: { $0.contains("calendar.read") }) ? "armed" : "standby"
                )
            )
        }

        if selectedPlugins.contains(where: { $0.id == "weather" }) {
            strategies.append(
                .init(
                    trigger: "天气接口失败",
                    strategy: "声明天气不可用，使用保守出行假设。",
                    fallback: "建议用户查看实时天气后再做户外安排。",
                    status: "armed"
                )
            )
        }

        if route.kind == .fileProcessing {
            strategies.append(
                .init(
                    trigger: "文件缺失或不可读",
                    strategy: "只基于用户可见文本回答，不编造文件内容。",
                    fallback: "请用户重新上传文本、Markdown、JSON 或 CSV。",
                    status: "armed"
                )
            )
        }

        strategies.append(
            .init(
                trigger: "上下文不足",
                strategy: "先给可执行假设，再列出需要补充的信息。",
                fallback: "询问一个最关键的澄清问题。",
                status: "always-on"
            )
        )
        return strategies
    }

    private func routePrompt(_ prompt: String) -> AgentRoute {
        let lowered = prompt.lowercased()
        let calendarWrite = [
            "add to calendar", "put on my calendar", "create calendar event",
            "write to calendar", "schedule it", "写进日历", "写到日历",
            "加到日历", "添加到日历", "放到日历", "创建日程", "写入日历"
        ]
        if calendarWrite.contains(where: lowered.contains) {
            return .init(kind: .calendarWrite, confidence: 0.93)
        }

        let fileProcessing = ["[file:", "本地文件上下文", "upload", "uploaded file", "file summary", "上传", "文件", "摘要", "knowledge", "rag", "知识库", "资料库"]
        if fileProcessing.contains(where: lowered.contains) {
            return .init(kind: .fileProcessing, confidence: 0.82)
        }

        let assignment = ["assignment", "homework", "作业", "大作业", "报告", "deadline", "截止", "提交"]
        if assignment.contains(where: lowered.contains) {
            return .init(kind: .assignmentPlanning, confidence: 0.86)
        }

        let weather = ["weather", "rain", "temperature", "wind", "outdoor", "天气", "下雨", "气温", "出门", "户外", "跑步"]
        if weather.contains(where: lowered.contains) {
            return .init(kind: .weatherDecision, confidence: 0.84)
        }

        let focus = ["focus", "pomodoro", "study", "deep work", "专注", "番茄钟", "复习", "学习", "冲刺"]
        if focus.contains(where: lowered.contains) {
            return .init(kind: .focusCoaching, confidence: 0.80)
        }

        let research = ["research", "literature", "paper", "citation", "论文", "文献", "调研", "研究", "引用"]
        if research.contains(where: lowered.contains) {
            return .init(kind: .researchPlanning, confidence: 0.76)
        }

        let agentArchitecture = [
            "agent", "plugin", "plugins", "skill", "skills", "memory", "mcp",
            "智能体", "插件", "技能", "记忆", "长期记忆", "工作记忆", "短期记忆", "架构"
        ]
        if agentArchitecture.contains(where: lowered.contains) {
            return .init(kind: .agentArchitecture, confidence: 0.88)
        }

        let schedule = [
            "calendar", "schedule", "agenda", "plan", "安排", "计划", "日程", "行程", "空闲", "会议",
            "待办", "有什么事", "有啥事", "要做什么", "今天要做", "今日要做",
            "today's schedule", "what do i have today", "available"
        ]
        if schedule.contains(where: lowered.contains) {
            return .init(kind: .schedulePlanning, confidence: 0.78)
        }

        return .init(kind: .generalChat, confidence: 0.58)
    }

    private func discoverPlugins(for route: AgentRoute, prompt: String) -> [AgentPluginMatch] {
        let lowered = prompt.lowercased()
        var routeIDs: [String]
        switch route.kind {
        case .calendarWrite:
            routeIDs = ["calendar", "memory", "skills", "safety", "trace"]
        case .schedulePlanning:
            routeIDs = ["calendar", "memory", "skills", "safety", "trace"]
        case .weatherDecision:
            let calendarNeeded = Self.weatherCalendarKeywords.contains(where: lowered.contains)
            routeIDs = calendarNeeded
                ? ["weather", "calendar", "memory", "safety", "trace"]
                : ["weather", "memory", "safety", "trace"]
        case .focusCoaching:
            routeIDs = ["focus", "calendar", "memory", "skills", "safety", "trace"]
        case .assignmentPlanning:
            routeIDs = ["assignment", "knowledge", "calendar", "focus", "memory", "skills", "safety", "trace"]
        case .agentArchitecture:
            routeIDs = ["memory", "knowledge", "skills", "planner", "reasoner", "reviewer", "recovery", "safety", "trace"]
        case .fileProcessing:
            routeIDs = ["shelf", "assignment", "knowledge", "memory", "skills", "recovery", "safety", "trace"]
        case .researchPlanning:
            routeIDs = ["knowledge", "memory", "skills", "planner", "reasoner", "reviewer", "recovery", "safety", "trace"]
        case .generalChat:
            routeIDs = ["memory", "safety", "trace"]
        }

        if !Defaults[.aiKnowledgeRetrievalEnabled] {
            routeIDs.removeAll { $0 == "knowledge" }
        }

        let hasProvidedFile = lowered.contains("[file:") || lowered.contains("本地文件上下文") || lowered.contains("上传")
        let asksKnowledge = ["knowledge", "rag", "资料库", "知识库", "study materials", "笔记"].contains { lowered.contains($0) }
        let knowledgeEnabled = Defaults[.aiKnowledgeRetrievalEnabled]
        let hasKnowledgeHit = knowledgeEnabled && AgentKnowledgeStore.shared.hasRelevantContent(for: prompt)
        let selectedIDs = Set(
            routeIDs
                + (hasProvidedFile ? ["shelf"] : [])
                + (knowledgeEnabled && (asksKnowledge || hasKnowledgeHit) ? ["knowledge"] : [])
        )

        return plugins.map { plugin in
            let keywordHits = plugin.discoveryKeywords.filter { lowered.contains($0.lowercased()) }.count
            let routeBoost = selectedIDs.contains(plugin.id) ? 0.58 : 0
            let keywordBoost = min(Double(keywordHits) * 0.12, 0.32)
            let alwaysOnBoost = ["safety", "trace"].contains(plugin.id) ? 0.14 : 0
            let score = min(routeBoost + keywordBoost + alwaysOnBoost, 0.99)
            let reason: String

            if selectedIDs.contains(plugin.id), keywordHits > 0 {
                reason = "路由匹配 + \(keywordHits) 个关键词"
            } else if selectedIDs.contains(plugin.id) {
                reason = "路由需要"
            } else if keywordHits > 0 {
                reason = "\(keywordHits) 个关键词命中"
            } else {
                reason = "暂不相关"
            }

            return AgentPluginMatch(
                id: plugin.id,
                pluginName: plugin.name,
                score: score,
                reason: reason,
                selected: selectedIDs.contains(plugin.id)
            )
        }
        .sorted { lhs, rhs in
            if lhs.selected != rhs.selected { return lhs.selected && !rhs.selected }
            return lhs.score > rhs.score
        }
    }

    private func skillsForRoute(_ route: AgentRoute, prompt: String) -> [AgentSkillDescriptor] {
        let lowered = prompt.lowercased()
        let routeSkillIDs: [String]

        switch route.kind {
        case .assignmentPlanning:
            routeSkillIDs = ["assignment_breakdown", "study_plan"]
        case .calendarWrite, .schedulePlanning:
            routeSkillIDs = ["calendar_aware_planning"]
        case .focusCoaching:
            routeSkillIDs = ["study_plan"]
        case .weatherDecision:
            routeSkillIDs = ["weather_decision"]
        case .agentArchitecture:
            routeSkillIDs = ["agent_memory_design"]
        case .fileProcessing:
            routeSkillIDs = ["file_context_analysis"]
        case .researchPlanning:
            routeSkillIDs = ["research_planning"]
        case .generalChat:
            routeSkillIDs = []
        }

        let routeSet = Set(routeSkillIDs)
        return skills.filter { skill in
            routeSet.contains(skill.id)
                || skill.triggerKeywords.contains(where: { lowered.contains($0.lowercased()) })
        }
    }

    private func permissionGateSummary(for plugins: [AgentPluginDescriptor], route: AgentRoute) -> String {
        let writeTools = plugins.flatMap(\.toolNames).filter { $0.contains("create") || $0.contains("start") || $0.contains("save") }

        guard !writeTools.isEmpty else {
            return "本轮只读上下文为主；无本地写动作。"
        }

        if route.kind == .calendarWrite {
            return "检测到写动作候选：\(writeTools.joined(separator: ", "))。日历写入必须满足：用户明确要求 + 设置允许 + 日历权限可用。"
        }

        return "检测到动作型工具 \(writeTools.joined(separator: ", "))，但当前路由不自动执行，只用于说明能力边界。"
    }

    private func weatherSummary() async -> String {
        let manager = WeatherManager.shared
        await manager.refreshWeather(force: false)

        guard let snapshot = manager.snapshot else {
            return manager.lastError.map { "天气不可用：\($0)" } ?? "天气不可用。"
        }

        let current = snapshot.current
        return "\(snapshot.locationName)：\(Int(current.temperature.rounded()))\(current.unitSymbol)，\(current.condition)，体感 \(Int(current.feelsLike.rounded()))\(current.unitSymbol)，风速 \(Int(current.windSpeed.rounded())) \(current.windUnit)，降水 \(String(format: "%.1f", current.precipitation)) mm。"
    }

    private func focusSummary() -> String {
        let manager = PomodoroManager.shared
        let state = manager.isRunning ? "运行中" : "待开始"
        return "番茄钟\(state)，阶段 \(manager.phase.rawValue)，剩余 \(manager.formattedRemaining)，默认专注 \(Defaults[.pomodoroFocusMinutes]) 分钟，已完成 \(manager.completedFocusSessions) 个专注段。"
    }

    private func preferenceSummary() -> String {
        let city = Defaults[.weatherCity].trimmingCharacters(in: .whitespacesAndNewlines)
        let cityLabel = city.isEmpty ? defaultWeatherCityName() : city
        return "日历上下文：\(Defaults[.aiCalendarContextEnabled] ? "开启" : "关闭")；日历写入：\(Defaults[.aiCalendarWriteEnabled] ? "开启" : "关闭")；天气城市：\(cityLabel)；默认专注/休息：\(Defaults[.pomodoroFocusMinutes])/\(Defaults[.pomodoroShortBreakMinutes]) 分钟。"
    }

    private func shortTermSummary(from messages: [AIChatMessage]) -> String {
        let recent = messages.suffix(6)
        guard !recent.isEmpty else {
            return "当前会话刚开始；无历史消息。"
        }

        return recent.map { message in
            let role = message.role == .user ? "user" : "assistant"
            let content = message.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "- \(role): \(String(content.prefix(180)))"
        }.joined(separator: "\n")
    }

    private func buildWorkingMemory(
        prompt: String,
        route: AgentRoute,
        selectedPlugins: [AgentPluginDescriptor],
        selectedSkills: [AgentSkillDescriptor]
    ) -> AgentWorkingMemory {
        let goal = "\(route.kind.displayName)：\(String(prompt.replacingOccurrences(of: "\n", with: " ").prefix(90)))"
        let entities = workingMemoryEntities(
            from: prompt,
            selectedPlugins: selectedPlugins,
            selectedSkills: selectedSkills
        )
        let pending = pendingQuestions(for: prompt, route: route)

        return AgentWorkingMemory(
            currentGoal: goal,
            taskProgress: "已完成路由、插件发现和上下文准备，等待模型生成回答。",
            keyEntities: entities,
            pendingQuestions: pending
        )
    }

    private func workingMemoryEntities(
        from prompt: String,
        selectedPlugins: [AgentPluginDescriptor],
        selectedSkills: [AgentSkillDescriptor]
    ) -> [String] {
        let lowered = prompt.lowercased()
        let candidates = [
            "短期记忆", "工作记忆", "长期记忆", "向量数据库", "Token", "日历", "天气", "作业",
            "番茄钟", "插件", "Skills", "MCP", "calendar", "weather", "assignment", "memory"
        ]
        var entities = candidates.filter { lowered.contains($0.lowercased()) }
        entities += selectedPlugins.map(\.name)
        entities += selectedSkills.map(\.name)

        if prompt.contains("[file:") || prompt.contains("本地文件上下文") {
            entities.append("上传文件")
        }

        var seen = Set<String>()
        return entities.filter { seen.insert($0).inserted }.prefix(12).map { $0 }
    }

    private func pendingQuestions(for prompt: String, route: AgentRoute) -> [String] {
        var questions: [String] = []
        let hasProvidedFile = prompt.contains("[file:") || prompt.contains("本地文件上下文")

        if route.kind == .assignmentPlanning && !hasProvidedFile {
            questions.append("是否需要上传作业要求或评分标准？")
        }
        if route.kind == .calendarWrite {
            questions.append("日历写入是否满足用户明确要求、设置允许和权限可用？")
        }
        if route.kind == .weatherDecision && !Defaults[.weatherFeatureEnabled] {
            questions.append("天气功能当前关闭，是否使用保守假设？")
        }

        return questions
    }

    private func longTermMemorySummary(_ memories: [AgentMemoryRecord]) -> String {
        guard !memories.isEmpty else {
            return "没有检索到与当前任务相关的长期记忆。"
        }

        return memories.enumerated().map { index, memory in
            let scoreText = memory.retrievalScore.map { String(format: "%.2f", $0) } ?? "n/a"
            let reasonText = memory.retrievalReason ?? "未记录"
            return "\(index + 1). [\(memory.kind.displayName)] \(memory.content) score=\(scoreText) reason=\(reasonText) keywords=\(memory.keywords.prefix(6).joined(separator: ", "))"
        }.joined(separator: "\n")
    }

    private func skillPlaybook(for route: AgentRoute, selectedSkills: [AgentSkillDescriptor]) -> String {
        if !selectedSkills.isEmpty {
            return selectedSkills.map { skill in
                """
                \(skill.name)：
                \(skill.workflowSteps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
                """
            }.joined(separator: "\n\n")
        }

        switch route.kind {
        case .assignmentPlanning:
            return "作业拆解技能：提取交付物，映射评分点，拆成里程碑，预留专注块，并指出缺失信息。"
        case .calendarWrite, .schedulePlanning:
            return "日程感知规划技能：寻找空闲窗口，避免冲突，使用绝对时间，并在创建事件前说明取舍。"
        case .focusCoaching:
            return "专注辅导技能：把目标拆成番茄钟大小的任务块，包含休息，保持计划现实。"
        default:
            return "通用助手技能：简洁回答，并说明使用了哪些本地上下文。"
        }
    }

    private func playbookName(for route: AgentRoute) -> String {
        switch route.kind {
        case .assignmentPlanning:
            return "作业拆解"
        case .calendarWrite, .schedulePlanning:
            return "日程感知规划"
        case .focusCoaching:
            return "专注辅导"
        default:
            return "通用助手"
        }
    }

    private func safetyNotes(for route: AgentRoute, contextBlocks: [String]) -> [String] {
        var notes = [
            "不要编造不可用的本地上下文。",
            "工具失败或权限不足影响答案时必须说明。",
        ]

        if route.kind == .calendarWrite {
            notes.append("只有在用户明确要求写入且设置允许时才创建日历事件。")
        }

        if contextBlocks.contains(where: { $0.contains("unavailable") || $0.contains("Disabled") }) {
            notes.append("至少一个工具没有返回可用上下文，需要降级推理。")
        }

        return notes
    }

    private func buildSystemContext(
        route: AgentRoute,
        taskUnderstanding: AgentTaskUnderstanding,
        reasoningProfile: AgentReasoningProfile,
        planSteps: [AgentPlanStep],
        recoveryStrategies: [AgentRecoveryStrategy],
        plugins: [AgentPluginDescriptor],
        skills: [AgentSkillDescriptor],
        contextBlocks: [String],
        safetyNotes: [String]
    ) -> String {
        let pluginLines = plugins.map {
            "- \($0.id): type=\($0.category); tools=\($0.toolNames.joined(separator: ", ")); permission=\($0.permission); risk=\($0.riskLevel)"
        }.joined(separator: "\n")
        let manifestLines = plugins.map {
            "- \($0.name): \($0.manifestPreview.replacingOccurrences(of: "\n", with: " "))"
        }.joined(separator: "\n")
        let skillLines = skills.isEmpty ? "本轮未装载专用 Skill。" : skills.map { skill in
            """
            - \(skill.name): required_tools=\(skill.requiredTools.joined(separator: ", ")); workflow=\(skill.workflowSteps.joined(separator: " -> "))
            """
        }.joined(separator: "\n")

        return """
        Boring Notch Agent 编排上下文：
        路由：\(route.kind.displayName)，置信度 \(String(format: "%.2f", route.confidence))。

        任务理解：
        \(taskUnderstanding.contextText)

        推理模式：
        \(reasoningProfile.contextText)

        计划步骤：
        \(planSteps.map { "\($0.order). \($0.title)：\($0.detail) [\($0.status)]" }.joined(separator: "\n"))

        已选择插件：
        \(pluginLines)

        插件 Manifest 摘要：
        \(manifestLines)

        已选择 Skills：
        \(skillLines)

        工具上下文：
        \(contextBlocks.joined(separator: "\n\n"))

        反思与安全护栏：
        \(safetyNotes.map { "- \($0)" }.joined(separator: "\n"))

        异常恢复策略：
        \(recoveryStrategies.map { "- \($0.trigger)：\($0.strategy) fallback=\($0.fallback)" }.joined(separator: "\n"))

        回复规则：
        - 相关时使用已选择的工具上下文；如果上下文显示工具失败，不要声称工具成功。
        - 如果知识库命中资料，优先基于 knowledge.retrieve 的摘要和 excerpt 回答；没有命中时明确说明未检索到相关资料。
        - 如果 Skills 已装载，按 workflow 输出过程型计划，不要只给泛泛建议。
        - 记忆上下文分为短期会话、工作记忆和长期记忆；长期记忆只代表检索命中的稳定信息，不要把普通聊天当成长期事实。
        - 日程或作业规划要给出具体步骤，并指出冲突或缺失信息。
        - 对本地风险动作，要清楚说明动作边界。
        """
    }
}

private extension AgentRoute.Kind {
    var displayName: String {
        switch self {
        case .generalChat:
            return "通用对话"
        case .schedulePlanning:
            return "日程规划"
        case .calendarWrite:
            return "日历写入"
        case .weatherDecision:
            return "天气决策"
        case .focusCoaching:
            return "专注辅导"
        case .assignmentPlanning:
            return "作业拆解"
        case .agentArchitecture:
            return "智能体架构"
        case .fileProcessing:
            return "文件处理"
        case .researchPlanning:
            return "研究规划"
        }
    }
}

@MainActor
final class AIChatManager: ObservableObject {
    static let shared = AIChatManager()

    @Published private(set) var conversations: [AgentChatConversation] = []
    @Published private(set) var activeConversationID: UUID?
    @Published private(set) var isSending: Bool = false
    @Published var lastError: String?
    @Published private(set) var lastResolvedModelName: String?
    @Published private(set) var lastAgentTrace: AgentRunTrace?
    @Published private(set) var knowledgeDocuments: [AgentKnowledgeDocument] = []

    private let conversationStoreURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let directory = Self.storageDirectory()
        conversationStoreURL = directory.appendingPathComponent("conversations.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadConversations()
        refreshKnowledgeDocuments()
    }

    var activeConversation: AgentChatConversation? {
        guard let activeConversationID else { return conversations.first }
        return conversations.first { $0.id == activeConversationID } ?? conversations.first
    }

    var messages: [AIChatMessage] {
        activeConversation?.messages ?? []
    }

    func clearConversation() {
        mutateActiveConversation { conversation in
            conversation.messages.removeAll()
            conversation.updatedAt = Date()
        }
        lastError = nil
        lastResolvedModelName = nil
        lastAgentTrace = nil
    }

    func appendLocalAssistantMessage(_ content: String) {
        appendMessage(AIChatMessage(role: .assistant, content: content))
    }

    func startNewConversation() {
        let conversation = AgentChatConversation(title: "新对话")
        conversations.insert(conversation, at: 0)
        activeConversationID = conversation.id
        lastError = nil
        lastAgentTrace = nil
        persistConversations()
    }

    func selectConversation(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        activeConversationID = id
        lastError = nil
        lastAgentTrace = nil
    }

    func deleteConversation(_ id: UUID) {
        guard conversations.count > 1 else {
            clearConversation()
            return
        }
        conversations.removeAll { $0.id == id }
        if activeConversationID == id {
            activeConversationID = conversations.first?.id
            lastError = nil
            lastAgentTrace = nil
        }
        persistConversations()
    }

    var displayedModelName: String {
        if let resolved = normalizedModelName(lastResolvedModelName) {
            return resolved
        }

        let configured = Defaults[.aiServiceModel].trimmingCharacters(in: .whitespacesAndNewlines)
        return configured.isEmpty ? "No model configured" : configured
    }

    var availablePlugins: [AgentPluginDescriptor] {
        AgentOrchestrator.shared.plugins
    }

    var availableSkills: [AgentSkillDescriptor] {
        AgentOrchestrator.shared.skills
    }

    var longTermMemories: [AgentMemoryRecord] {
        AgentMemoryStore.shared.recentRecords
    }

    var longTermMemoryLocation: URL {
        AgentMemoryStore.shared.storageURL
    }

    var knowledgeStorageLocation: URL {
        AgentKnowledgeStore.shared.storageURL
    }

    func refreshKnowledgeDocuments() {
        knowledgeDocuments = AgentKnowledgeStore.shared.documents
    }

    @discardableResult
    func addKnowledgeDocument(
        name: String,
        path: String,
        content: String,
        byteCount: Int
    ) -> AgentKnowledgeDocument? {
        let document = AgentKnowledgeStore.shared.addDocument(
            title: name,
            sourcePath: path,
            content: content,
            byteCount: byteCount
        )
        if document != nil {
            refreshKnowledgeDocuments()
        }
        return document
    }

    func removeKnowledgeDocument(id: UUID) {
        AgentKnowledgeStore.shared.removeDocument(id: id)
        refreshKnowledgeDocuments()
    }

    func clearKnowledgeBase() {
        AgentKnowledgeStore.shared.clear()
        refreshKnowledgeDocuments()
    }

    @discardableResult
    func installStarterKnowledgeBase() -> Int {
        var importedCount = 0
        for seed in Self.starterKnowledgeDocuments {
            let content = seed.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            if AgentKnowledgeStore.shared.addDocument(
                title: seed.title,
                sourcePath: seed.sourcePath,
                content: content,
                byteCount: content.utf8.count
            ) != nil {
                importedCount += 1
            }
        }
        refreshKnowledgeDocuments()
        return importedCount
    }

    func revealKnowledgeBaseFile() {
        let store = AgentKnowledgeStore.shared
        if !FileManager.default.fileExists(atPath: store.storageURL.path) {
            store.clear()
            refreshKnowledgeDocuments()
        }
        NSWorkspace.shared.activateFileViewerSelecting([store.storageURL])
    }

    @discardableResult
    func rememberMemory(_ content: String) -> AgentMemoryRecord? {
        let record = AgentMemoryStore.shared.storeManual(content)
        if record != nil {
            objectWillChange.send()
        }
        return record
    }

    @discardableResult
    func forgetMemory(matching query: String = "") -> Int {
        let removedCount = AgentMemoryStore.shared.forget(matching: query)
        if removedCount > 0 {
            objectWillChange.send()
        }
        return removedCount
    }

    func clearLongTermMemory() {
        AgentMemoryStore.shared.clear()
        objectWillChange.send()
    }

    func revealLongTermMemoryFile() {
        NSWorkspace.shared.activateFileViewerSelecting([AgentMemoryStore.shared.storageURL])
    }

    func send(prompt: String, displayPrompt: String? = nil) async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !isSending else { return }

        appendMessage(AIChatMessage(role: .user, content: displayPrompt ?? trimmedPrompt))
        lastError = nil
        isSending = true
        defer { isSending = false }

        do {
            var agentRun = await AgentOrchestrator.shared.prepare(prompt: trimmedPrompt, recentMessages: messages)
            lastAgentTrace = agentRun.trace
            let reply: AIReply

            if agentRun.route.kind == .calendarWrite {
                reply = try await requestCalendarWriteReply(
                    for: trimmedPrompt,
                    agentRun: agentRun
                )
            } else {
                reply = try await requestReply(
                    for: trimmedPrompt,
                    agentRun: agentRun
                )
            }

            lastResolvedModelName = reply.resolvedModelName ?? reply.requestedModelName
            appendMessage(AIChatMessage(role: .assistant, content: reply.content))
            agentRun.trace.status = "已完成"
            agentRun.trace.steps.append(
                .init(
                    title: "模型回复",
                    detail: "实际模型：\(reply.resolvedModelName ?? reply.requestedModelName)",
                    status: "done"
                )
            )
            lastAgentTrace = agentRun.trace
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if var trace = lastAgentTrace {
                trace.status = "Failed"
                trace.steps.append(
                    .init(
                        title: "失败",
                        detail: lastError ?? "Unknown error",
                        status: "error"
                    )
                )
                lastAgentTrace = trace
            }
        }
    }

    private static func storageDirectory() -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? temporaryDirectory
        return baseDirectory.appendingPathComponent("DanShenAgent", isDirectory: true)
    }

    private func loadConversations() {
        if let data = try? Data(contentsOf: conversationStoreURL),
           let decoded = try? decoder.decode([AgentChatConversation].self, from: data),
           !decoded.isEmpty
        {
            conversations = decoded.sorted { $0.updatedAt > $1.updatedAt }
            activeConversationID = conversations.first?.id
            return
        }

        let starter = AgentChatConversation(title: "新对话")
        conversations = [starter]
        activeConversationID = starter.id
        persistConversations()
    }

    private func persistConversations() {
        guard let data = try? encoder.encode(conversations) else { return }
        try? data.write(to: conversationStoreURL, options: .atomic)
    }

    private func appendMessage(_ message: AIChatMessage) {
        if conversations.isEmpty {
            startNewConversation()
        }

        mutateActiveConversation { conversation in
            if conversation.messages.isEmpty, message.role == .user {
                conversation.title = Self.title(from: message.content)
            }
            conversation.messages.append(message)
            conversation.updatedAt = message.createdAt
        }
    }

    private func mutateActiveConversation(_ mutate: (inout AgentChatConversation) -> Void) {
        if conversations.isEmpty {
            let starter = AgentChatConversation(title: "新对话")
            conversations = [starter]
            activeConversationID = starter.id
        }

        let resolvedID = activeConversationID ?? conversations.first?.id
        guard let resolvedID,
              let index = conversations.firstIndex(where: { $0.id == resolvedID })
        else { return }

        mutate(&conversations[index])
        conversations.sort { $0.updatedAt > $1.updatedAt }
        activeConversationID = resolvedID
        persistConversations()
    }

    private static func title(from prompt: String) -> String {
        let withoutFiles = prompt
            .components(separatedBy: "本地文件上下文：")
            .first ?? prompt
        let normalized = withoutFiles
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "用户问题：", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "新对话" : String(normalized.prefix(18))
    }

    private static let starterKnowledgeDocuments: [(title: String, sourcePath: String, content: String)] = [
        (
            "GitHub 案例：Agent Skills 渐进式加载",
            "seed://github-agent-skills-progressive-disclosure",
            """
            # GitHub 案例：Agent Skills 渐进式加载

            适合Boring Notch Agent 的结论：Skills 不是普通 prompt 集合，而是“按需加载的任务流程包”。一个 Skill 通常由 SKILL.md 作为入口，使用 YAML frontmatter 描述名称、触发描述、权限或工具边界，再用 Markdown 写执行步骤。复杂 Skill 可以把长参考资料、模板、脚本放在同目录，只有任务需要时才读取，避免每轮对话塞满上下文。

            对我们的实现启发：
            1. 插件负责“能拿到什么上下文/能做什么动作”，Skill 负责“这类任务应该按什么流程做”。
            2. Skill 的 description 应该写成触发条件，不只是说明文字，例如“当用户要求把作业要求拆成评分点、里程碑和日程计划时使用”。
            3. 支持文件可以被延迟读取，适合study materials、评分标准模板、论文写作模板。
            4. 有副作用的技能不要自动运行，例如写日历、发消息、删除文件，应该用确认门控。

            Boring Notch可落地设计：
            - skills/study-plan/SKILL.md：复习计划流程。
            - skills/assignment-breakdown/SKILL.md：作业拆解流程。
            - skills/weather-decision/SKILL.md：天气 + 日程的出行建议流程。
            - skills/agent-memory-design/SKILL.md：短期/工作/长期记忆说明。

            和 Claude/Codex/Roo 的对应关系：
            - Codex: openai/skills 仓库提供可安装 Skill catalog。
            - Claude Code: 个人、项目、插件级 skills 都以 SKILL.md 为入口，description 用于自动加载。
            - Roo Code: 先索引 frontmatter，命中后再读取完整 SKILL.md，属于典型 progressive disclosure。

            Sources:
            - https://github.com/openai/skills
            - https://code.claude.com/docs/en/skills
            - https://roocodeinc.github.io/Roo-Code/features/skills
            """
        ),
        (
            "GitHub 案例：Cline/Roo 的插件与 MCP 思路",
            "seed://github-cline-roo-mcp-plugin-patterns",
            """
            # GitHub 案例：Cline/Roo 的插件与 MCP 思路

            适合Boring Notch Agent 的结论：现代 agent host 一般不把所有能力写死在 prompt 里，而是把能力拆成插件、工具、资源和提示模板。Cline 支持通过 SDK 注册工具和生命周期 hooks，也能通过 MCP server 扩展外部数据源和动作；Roo Code 把 MCP 配置分成全局和项目级，并强调工具需要明确配置和审批。

            对我们的实现启发：
            1. Plugin Registry：每个插件有 id、类型、工具名、权限和风险等级。
            2. Tool Discovery：先根据用户任务选相关插件，不一次性把所有工具上下文塞给模型。
            3. Context Plugin 和 Action Plugin 分开：天气、知识库、日历读取属于 context；写日历、启动计时器属于 action。
            4. Permission Gate：读操作可以自动，写操作必须设置允许并由用户明确请求。
            5. Trace Logger：记录本轮路由、命中插件、上下文准备和安全检查，方便product demonstration“智能体不是黑箱”。

            Boring Notch可以对齐的 MCP 分层：
            - Tools：weather.current、calendar.create_event、memory.save_preference。
            - Resources：本地知识库文档、study materials、拖入文件、日历上下文。
            - Prompts：/skills、/knowledge、作业拆解模板、天气决策模板。

            最小可演示架构：
            User Prompt -> Agent Router -> Plugin Registry -> Tool Discovery -> Context Gathering -> Skill Playbook -> Permission Gate -> LLM Reply -> Trace Logger

            Sources:
            - https://github.com/cline/cline
            - https://docs.cline.bot/mcp/mcp-overview
            - https://roocodeinc.github.io/Roo-Code/features/mcp/using-mcp-in-roo
            - https://modelcontextprotocol.io/specification/2025-06-18/server/tools
            - https://modelcontextprotocol.io/docs/concepts/prompts
            """
        ),
        (
            "GitHub 案例：知识库与记忆的边界",
            "seed://agent-memory-vs-knowledge-base-boundary",
            """
            # GitHub 案例：知识库与记忆的边界

            适合Boring Notch Agent 的结论：知识库不等于长期记忆。知识库存的是用户显式导入的资料，例如课程文档、作业要求、论文笔记、项目说明；长期记忆存的是跨会话稳定偏好和事实，例如“我喜欢晚上学习”“默认 45 分钟专注”。两者都可以检索，但写入策略不同。

            三层记忆：
            - 短期记忆：当前会话最近消息，只影响当前聊天页。
            - 工作记忆：当前任务目标、进度、实体、待澄清问题，来自本轮 agent trace。
            - 长期记忆：明确请求“记住”后写入，跨会话可检索。

            知识库策略：
            - 导入：只接受用户显式选择的文件，避免偷偷读取本地隐私。
            - 检索：先做关键词和语义词粗检索，再按时间和命中质量排序。
            - 注入：只把 Top-3 相关片段放进上下文，避免污染回答。
            - 展示：面板显示资料来源、摘要、关键词和大小，方便用户知道 agent 用了什么。

            演示问法：
            - “根据知识库里的作业要求，帮我列评分点。”
            - “我之前导入的智能体资料里，插件和 skill 有什么区别？”
            - “用知识库内容解释 MCP 的 tools/resources/prompts。”

            和 Skills 的关系：
            Skill 是流程说明，知识库是资料来源。比如 assignment-breakdown skill 规定怎么拆作业；知识库存储具体 assignment requirements。两者结合才像真正的桌面 agent。

            Sources:
            - https://code.claude.com/docs/en/skills
            - https://roocodeinc.github.io/Roo-Code/features/skills
            - https://modelcontextprotocol.io/docs/concepts/prompts
            """
        ),
        (
            "GitHub 案例：安全护栏与插件权限",
            "seed://agent-plugin-safety-permission-model",
            """
            # GitHub 案例：安全护栏与插件权限

            适合Boring Notch Agent 的结论：插件系统的难点不是“能调用多少工具”，而是“什么时候不该调用”。Cline、Roo、MCP 文档都把外部工具视为可扩展能力，但同时需要配置、确认、权限和错误处理。对 macOS 桌面应用来说，安全模型尤其重要，因为工具可能影响日历、本地文件、App 启动或用户隐私。

            插件权限建议：
            - read:auto：天气、只读日历、知识库检索、长期记忆检索。
            - write:explicit：用户明确说“记住”才写长期记忆。
            - write:settings-gated：写日历必须设置允许 + 用户明确请求。
            - action:user-triggered：启动番茄钟、打开 App、分享文件必须可见触发。
            - deny-by-default：删除文件、上传隐私数据、执行未知脚本默认拒绝。

            Trace 需要记录：
            1. 为什么选择这个插件。
            2. 插件权限是什么。
            3. 工具成功、跳过还是降级。
            4. 如果信息缺失，模型是否说明了缺口。
            5. 写操作是否经过用户确认。

            报告可写的亮点：
            - Progressive tool discovery 降低 prompt 噪声。
            - Human-in-the-loop 防止危险动作。
            - Tool permission model 区分只读、写入、动作和拒绝。
            - Agent trace 提升可解释性。
            - Knowledge base 只读取用户显式导入资料，符合隐私边界。

            Sources:
            - https://github.com/cline/cline
            - https://docs.cline.bot/mcp/mcp-overview
            - https://roocodeinc.github.io/Roo-Code/features/mcp/using-mcp-in-roo
            - https://modelcontextprotocol.io/specification/2025-06-18/server/tools
            """
        ),
        (
            "GitHub 案例：Boring Notch Agent product demo 脚本",
            "seed://boring-notch-agent-course-demo-script",
            """
            # GitHub 案例：Boring Notch Agent product demo 脚本

            目标：展示Boring Notch不是普通聊天框，而是一个 macOS 桌面 Agent Host。

            Demo 1：多会话短期记忆
            1. 新建会话 A，问“帮我记住这轮我们在做天气插件演示”。
            2. 新建会话 B，问“刚才这个会话说了什么？”。
            3. 解释：短期记忆按会话隔离，长期记忆只有明确 /remember 或“请记住”才跨会话。

            Demo 2：知识库检索
            1. 点击知识库，导入 GitHub 示例知识库。
            2. 问“根据知识库，Skill 和 Plugin 有什么区别？”。
            3. 展示 trace 中 knowledge.retrieve 命中，说明它不是泛泛回答。

            Demo 3：插件路由
            1. 问“今天天气怎么样，适合出去跑步吗？”。
            2. 展示 weather、memory、safety、trace 插件。
            3. 说明天气插件是 Context Plugin，只读；不会做写操作。

            Demo 4：权限门控
            1. 问“把明天下午三点的复习写进日历”。
            2. 展示 calendar action 插件和 Permission Gate。
            3. 说明写入需要设置允许和用户明确请求。

            Demo 5：Skills
            1. 输入 /skills。
            2. 展示 study-plan、assignment-breakdown、weather-decision、Nature 学术类 skill。
            3. 说明 Skill 是任务流程，Plugin 是工具能力，Knowledge 是资料来源，Memory 是用户状态。

            可以放进报告的一句话：
            Boring Notch Agent 将 macOS notch utility 升级为桌面 Agent Host：通过插件注册表、渐进式工具发现、Skill 工作流、本地知识库、三层记忆和权限护栏，把聊天界面变成可解释、可扩展、可控的智能体系统。
            """
        ),
    ]

    private func requestReply(for prompt: String, agentRun: AgentPreparedRun) async throws -> AIReply {
        let config = try resolveServiceConfig()
        let decoded = try await performChatCompletion(
            config: config,
            messages: buildPayloadMessages(
                requestedModel: config.requestedModel,
                calendarContext: agentRun.calendarContext,
                agentContext: agentRun.systemContext
            ),
            temperature: configuredTemperature()
        )
        let resolvedModelName = normalizedModelName(decoded.model) ?? config.requestedModel

        if isModelIdentityQuestion(prompt) {
            return AIReply(
                content: localizedModelIdentityReply(
                    for: prompt,
                    resolvedModelName: resolvedModelName
                ),
                requestedModelName: config.requestedModel,
                resolvedModelName: resolvedModelName
            )
        }

        let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !content.isEmpty else {
            throw FeatureError("The AI service returned an empty response.")
        }

        return AIReply(
            content: content,
            requestedModelName: config.requestedModel,
            resolvedModelName: resolvedModelName
        )
    }

    private func requestCalendarWriteReply(for prompt: String, agentRun: AgentPreparedRun) async throws -> AIReply {
        guard Defaults[.aiCalendarWriteEnabled] else {
            throw FeatureError("AI calendar writing is disabled in Settings > AI.")
        }

        guard agentRun.calendarContext != nil else {
            throw FeatureError("Calendar access is unavailable. Enable it in Settings > Calendar before asking AI to write plans.")
        }

        let config = try resolveServiceConfig()
        let decoded = try await performChatCompletion(
            config: config,
            messages: buildPayloadMessages(
                requestedModel: config.requestedModel,
                calendarContext: agentRun.calendarContext,
                agentContext: agentRun.systemContext,
                extraSystemMessages: [calendarWriteInstruction()]
            ),
            temperature: configuredTemperature(maximum: 0.2)
        )

        let resolvedModelName = normalizedModelName(decoded.model) ?? config.requestedModel
        let rawContent = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let action = try decodeCalendarAction(from: rawContent)

        let drafts = try action.events.compactMap { try makeCalendarDraft(from: $0) }
        let createdEvents: [CreatedCalendarEvent]

        if action.createEvents && !drafts.isEmpty {
            createdEvents = try await CalendarManager.shared.createAIPlannedEvents(drafts)
        } else {
            createdEvents = []
        }

        let content = mergedCalendarWriteReply(baseReply: action.reply, createdEvents: createdEvents)
        return AIReply(
            content: content,
            requestedModelName: config.requestedModel,
            resolvedModelName: resolvedModelName
        )
    }

    private func buildPayloadMessages(
        requestedModel: String,
        calendarContext: String? = nil,
        agentContext: String? = nil,
        extraSystemMessages: [String] = []
    ) -> [OpenAIChatRequest.Message] {
        var payloadMessages: [OpenAIChatRequest.Message] = []
        let systemPrompt = Defaults[.aiSystemPrompt].trimmingCharacters(in: .whitespacesAndNewlines)

        if !systemPrompt.isEmpty {
            payloadMessages.append(.init(role: "system", content: systemPrompt))
        }

        payloadMessages.append(
            .init(
                role: "system",
                content: """
                The requested model name for this chat is "\(requestedModel)".
                If the user asks which model is responding, answer with that exact model name unless the API metadata for the current response proves otherwise.
                Do not claim to be GPT-4o or any other different model name.
                """
            )
        )

        payloadMessages.append(.init(role: "system", content: groundingInstruction()))

        if let calendarContext, !calendarContext.isEmpty {
            payloadMessages.append(
                .init(
                    role: "system",
                    content: """
                    The user's local time zone is \(TimeZone.current.identifier).
                    The current local date and time is \(isoTimestamp(Date())).
                    Use the following calendar context only when it is relevant to the request:
                    \(calendarContext)
                    """
                )
            )
        }

        if let agentContext, !agentContext.isEmpty {
            payloadMessages.append(
                .init(
                    role: "system",
                    content: agentContext
                )
            )
        }

        payloadMessages.append(
            contentsOf: extraSystemMessages.map { .init(role: "system", content: $0) }
        )

        let history = messages.suffix(12)
        payloadMessages.append(
            contentsOf: history.map {
                OpenAIChatRequest.Message(role: $0.role.rawValue, content: $0.content)
            }
        )

        return payloadMessages
    }

    private func chatCompletionsURL(from baseURL: String) -> URL? {
        guard !baseURL.isEmpty else { return nil }

        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        let lowercased = trimmed.lowercased()
        let sanitizedLowercased = sanitized.lowercased()

        if lowercased.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }
        if sanitizedLowercased.hasSuffix("/v1") {
            return URL(string: sanitized + "/chat/completions")
        }
        return URL(string: sanitized + "/v1/chat/completions")
    }

    private func normalizedModelName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolveServiceConfig() throws -> AIServiceConfig {
        let baseURL = Defaults[.aiServiceBaseURL].trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = Defaults[.aiServiceAPIKey].trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedModel = Defaults[.aiServiceModel].trimmingCharacters(in: .whitespacesAndNewlines)

        guard Defaults[.aiChatEnabled] else {
            throw FeatureError("AI chat is disabled in Settings.")
        }

        guard !apiKey.isEmpty else {
            throw FeatureError("Missing API key. Set it in Settings > AI.")
        }

        guard !requestedModel.isEmpty else {
            throw FeatureError("Missing model name. Set it in Settings > AI.")
        }

        guard let endpoint = chatCompletionsURL(from: baseURL) else {
            throw FeatureError("Invalid AI base URL.")
        }

        return AIServiceConfig(endpoint: endpoint, apiKey: apiKey, requestedModel: requestedModel)
    }

    private func configuredTemperature(maximum: Double = 1.0) -> Double {
        min(max(Defaults[.aiTemperature], 0.0), maximum)
    }

    private func groundingInstruction() -> String {
        """
        Grounding and local-context rules:
        - Do not invent local calendar events, today's schedule, reminders, files, weather, memory, or knowledge-base content.
        - If the user asks about today's plan, schedule, agenda, free time, meetings, or calendar, answer only from the provided calendar context.
        - If calendar context is missing, disabled, permission-denied, or empty, say that you cannot confirm local schedule from the calendar; do not fabricate events.
        - If a retrieved memory or knowledge-base excerpt is absent, state that no relevant local record was found.
        - Keep answers concise unless the user asks for a detailed plan.
        """
    }

    private func performChatCompletion(
        config: AIServiceConfig,
        messages: [OpenAIChatRequest.Message],
        temperature: Double
    ) async throws -> OpenAIChatResponse {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let payload = OpenAIChatRequest(
            model: config.requestedModel,
            messages: messages,
            temperature: temperature
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200 ... 299).contains(httpResponse.statusCode) {
            if let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data),
               let message = apiError.error.message, !message.isEmpty
            {
                throw FeatureError(message)
            }
            throw FeatureError("AI request failed with status \(httpResponse.statusCode).")
        }

        return try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
    }

    private func calendarContextIfRelevant(for prompt: String) async -> String? {
        guard wantsCalendarContext(for: prompt) else { return nil }
        return await CalendarManager.shared.aiScheduleContext()
    }

    private func wantsCalendarContext(for prompt: String) -> Bool {
        guard Defaults[.aiCalendarContextEnabled] else { return false }

        let lowered = prompt.lowercased()
        let keywords = [
            "calendar",
            "schedule",
            "agenda",
            "plan",
            "安排",
            "计划",
            "日程",
            "日历",
            "行程",
            "空闲",
            "提醒",
            "会议",
            "待办",
            "有什么事",
            "有啥事",
            "要做什么",
            "今天要做",
            "今日要做",
            "today's schedule",
            "what do i have today",
            "什么时候有空",
            "when am i free",
            "available"
        ]
        return keywords.contains(where: lowered.contains)
    }

    private func wantsCalendarWrite(for prompt: String) -> Bool {
        guard Defaults[.aiCalendarWriteEnabled] else { return false }

        let lowered = prompt.lowercased()
        let keywords = [
            "add to calendar",
            "put on my calendar",
            "create calendar event",
            "write to calendar",
            "schedule it",
            "写进日历",
            "写到日历",
            "加到日历",
            "添加到日历",
            "放到日历",
            "创建日程",
            "创建日历",
            "写入日历"
        ]
        return keywords.contains(where: lowered.contains)
    }

    private func calendarWriteInstruction() -> String {
        """
        You are creating calendar events for the user.
        Return only a JSON object with this exact schema:
        {
          "reply": "short natural-language confirmation in the user's language",
          "create_events": true,
          "events": [
            {
              "title": "event title",
              "start": "ISO-8601 local date-time with timezone offset",
              "end": "ISO-8601 local date-time with timezone offset",
              "notes": "optional notes",
              "location": "optional location"
            }
          ]
        }

        Rules:
        - Use the user's existing calendar schedule to avoid conflicts.
        - Use absolute timestamps, never relative phrases.
        - Keep event titles short and practical.
        - If the user asked for a study/work plan, split it into sensible time blocks.
        - If required timing is unclear, make a reasonable plan based on free time in the calendar.
        - Return JSON only. No markdown fences.
        """
    }

    private func decodeCalendarAction(from rawContent: String) throws -> AICalendarWriteAction {
        guard let jsonString = extractJSONObject(from: rawContent),
              let data = jsonString.data(using: .utf8)
        else {
            throw FeatureError("The AI did not return a usable calendar plan.")
        }

        do {
            return try JSONDecoder().decode(AICalendarWriteAction.self, from: data)
        } catch {
            throw FeatureError("The AI returned an invalid calendar plan format.")
        }
    }

    private func extractJSONObject(from rawContent: String) -> String? {
        guard let start = rawContent.firstIndex(of: "{"),
              let end = rawContent.lastIndex(of: "}")
        else {
            return nil
        }
        return String(rawContent[start...end])
    }

    private func makeCalendarDraft(from payload: AICalendarEventPayload) throws -> CalendarEventDraft? {
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        guard let start = parseCalendarDate(payload.start),
              let end = parseCalendarDate(payload.end)
        else {
            throw FeatureError("The AI returned a calendar event with an invalid date.")
        }

        return CalendarEventDraft(
            title: title,
            start: start,
            end: end,
            notes: normalizedOptionalText(payload.notes),
            location: normalizedOptionalText(payload.location)
        )
    }

    private func parseCalendarDate(_ rawValue: String) -> Date? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let internetFormatter = ISO8601DateFormatter()
        internetFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = internetFormatter.date(from: value) {
            return parsed
        }

        let fallbackInternetFormatter = ISO8601DateFormatter()
        fallbackInternetFormatter.formatOptions = [.withInternetDateTime]
        if let parsed = fallbackInternetFormatter.date(from: value) {
            return parsed
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: value) {
                return parsed
            }
        }

        return nil
    }

    private func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func mergedCalendarWriteReply(
        baseReply: String,
        createdEvents: [CreatedCalendarEvent]
    ) -> String {
        let trimmedReply = baseReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !createdEvents.isEmpty else {
            return trimmedReply.isEmpty ? "已生成计划，但没有写入新的日历事件。" : trimmedReply
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "MM-dd HH:mm"

        let lines = createdEvents.map {
            "- \($0.title) (\(formatter.string(from: $0.start)) - \(formatter.string(from: $0.end)))"
        }
        let creationSummary = "已写入日历：\n" + lines.joined(separator: "\n")

        if trimmedReply.isEmpty {
            return creationSummary
        }

        return trimmedReply + "\n\n" + creationSummary
    }

    private func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private func isModelIdentityQuestion(_ prompt: String) -> Bool {
        let lowered = prompt.lowercased()
        let keywords = [
            "what model",
            "which model",
            "model are you",
            "your model",
            "模型",
            "什么模型",
            "哪个模型",
            "你是什么模型",
            "真实模型"
        ]
        return keywords.contains(where: lowered.contains)
    }

    private func localizedModelIdentityReply(for prompt: String, resolvedModelName: String) -> String {
        if prompt.containsChineseCharacters {
            return "当前接口实际返回的模型是 \(resolvedModelName)。"
        }
        return "The current model returned by the API is \(resolvedModelName)."
    }
}

private struct WeatherLookupLocation {
    let displayName: String
    let latitude: Double
    let longitude: Double
}

private final class WeatherLocationProvider: NSObject, CLLocationManagerDelegate {
    var authorizationDidChange: ((CLAuthorizationStatus) -> Void)?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func ensureAuthorizationStatus() async -> CLAuthorizationStatus {
        let status = authorizationStatus
        guard status == .notDetermined else { return status }

        await MainActor.run {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }

        try? await Task.sleep(for: .milliseconds(300))

        await MainActor.run {
            manager.requestWhenInUseAuthorization()
        }

        var resolvedStatus = authorizationStatus
        for _ in 0..<20 {
            if resolvedStatus != .notDetermined {
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
            resolvedStatus = authorizationStatus
        }

        if resolvedStatus != .notDetermined {
            await MainActor.run {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        return resolvedStatus
    }

    func requestResolvedLocation() async throws -> WeatherLookupLocation {
        let status = await ensureAuthorizationStatus()
        let servicesEnabled = CLLocationManager.locationServicesEnabled()

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            guard servicesEnabled else {
                throw FeatureError("Location Services are disabled in macOS settings.")
            }
            break
        case .denied:
            throw FeatureError("Location access is denied. Allow Boring Notch in Privacy & Security > Location Services.")
        case .restricted:
            throw FeatureError("Location access is restricted on this Mac.")
        case .notDetermined:
            if !servicesEnabled {
                throw FeatureError("Location Services are disabled in macOS settings.")
            }
            throw FeatureError("Location access has not been granted yet.")
        @unknown default:
            throw FeatureError("Location access is unavailable.")
        }

        let location = try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }

        return WeatherLookupLocation(
            displayName: await reverseGeocodeDisplayName(for: location) ?? "Current location",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        authorizationDidChange?(status)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil

        if let location = locations.last {
            continuation.resume(returning: location)
        } else {
            continuation.resume(throwing: FeatureError("Current location was unavailable."))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(throwing: error)
    }

    private func reverseGeocodeDisplayName(for location: CLLocation) async -> String? {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            return [placemark.locality, placemark.administrativeArea, placemark.country]
                .compactMap { component in
                    guard let component, !component.isEmpty else { return nil }
                    return component
                }
                .joined(separator: ", ")
        } catch {
            return nil
        }
    }
}

@MainActor
final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isRefreshing: Bool = false
    @Published var lastError: String?
    @Published private(set) var locationServicesEnabled: Bool
    @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus

    private var cancellables: Set<AnyCancellable> = []
    private let locationProvider: WeatherLocationProvider

    private init() {
        locationProvider = WeatherLocationProvider()
        locationServicesEnabled = CLLocationManager.locationServicesEnabled()
        locationAuthorizationStatus = locationProvider.authorizationStatus

        let cityPublisher = Defaults.publisher(.weatherCity).map { _ in () }.eraseToAnyPublisher()
        let modePublisher = Defaults.publisher(.weatherLocationMode).map { _ in () }.eraseToAnyPublisher()
        let unitPublisher = Defaults.publisher(.weatherTemperatureUnit).map { _ in () }.eraseToAnyPublisher()
        let enabledPublisher = Defaults.publisher(.weatherFeatureEnabled).map { _ in () }.eraseToAnyPublisher()

        Publishers.Merge4(cityPublisher, modePublisher, unitPublisher, enabledPublisher)
            .sink { [weak self] _ in
                Task { await self?.refreshWeather(force: true) }
            }
            .store(in: &cancellables)

        locationProvider.authorizationDidChange = { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.locationAuthorizationStatus = status

                guard Defaults[.weatherFeatureEnabled], Defaults[.weatherLocationMode] == .automatic else { return }
                await self.refreshWeather(force: true)
            }
        }

        Task {
            await refreshWeather(force: false)
        }
    }

    var locationAuthorizationDescription: String {
        if !locationServicesEnabled {
            return "Services off"
        }

        switch locationAuthorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Allowed"
        case .notDetermined:
            return "Not requested"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unknown"
        }
    }

    func requestLocationAuthorization() async {
        await MainActor.run {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        refreshLocationAccessState()
        let status = await locationProvider.ensureAuthorizationStatus()
        locationAuthorizationStatus = status

        switch status {
        case .denied, .restricted, .notDetermined:
            break
        default:
            await refreshWeather(force: true)
        }

        if status != .notDetermined {
            await MainActor.run {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func openLocationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshWeather(force: Bool) async {
        refreshLocationAccessState()

        guard Defaults[.weatherFeatureEnabled] else {
            snapshot = nil
            lastError = nil
            return
        }

        guard !isRefreshing else { return }

        if let snapshot, !force, Date().timeIntervalSince(snapshot.updatedAt) < 900 {
            return
        }

        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            let location = try await resolvedLocation()
            snapshot = try await fetchWeather(for: location)
        } catch {
            if snapshot == nil {
                snapshot = nil
            }
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshLocationAccessState() {
        locationServicesEnabled = CLLocationManager.locationServicesEnabled()
        locationAuthorizationStatus = locationProvider.authorizationStatus
    }

    private func resolvedLocation() async throws -> WeatherLookupLocation {
        if Defaults[.weatherLocationMode] == .automatic {
            return try await locationProvider.requestResolvedLocation()
        }

        let query = Defaults[.weatherCity].trimmingCharacters(in: .whitespacesAndNewlines)
        let city = query.isEmpty ? defaultWeatherCityName() : query

        guard !city.isEmpty else {
            throw FeatureError("请先在设置 > Weather 中填写城市。")
        }

        return try await geocode(city: city)
    }

    private func geocode(city: String) async throws -> WeatherLookupLocation {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components?.url else {
            throw FeatureError("天气城市查询地址无效。")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200 ... 299).contains(httpResponse.statusCode) {
            throw FeatureError("天气城市查询失败，状态码 \(httpResponse.statusCode)。")
        }

        let decoded = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        guard let firstMatch = decoded.results?.first else {
            throw FeatureError("没有找到“\(city)”的天气结果。")
        }

        return .init(
            displayName: firstMatch.displayName,
            latitude: firstMatch.latitude,
            longitude: firstMatch.longitude
        )
    }

    private func fetchWeather(for location: WeatherLookupLocation) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        let unit = Defaults[.weatherTemperatureUnit]
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m,is_day"
            ),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: unit.apiValue),
            URLQueryItem(name: "wind_speed_unit", value: unit.windSpeedAPIValue),
        ]

        guard let url = components?.url else {
            throw FeatureError("天气预报地址无效。")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200 ... 299).contains(httpResponse.statusCode) {
            throw FeatureError("天气获取失败，状态码 \(httpResponse.statusCode)。")
        }

        let decoded = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
        let currentDescriptor = WeatherDescriptor.from(code: decoded.current.weatherCode, isDay: decoded.current.isDay == 1)
        let hourlySlice = hourlyEntries(from: decoded.hourly, currentTime: decoded.current.time, unit: unit)

        return WeatherSnapshot(
            locationName: location.displayName,
            updatedAt: Date(),
            current: .init(
                temperature: decoded.current.temperature,
                feelsLike: decoded.current.apparentTemperature,
                humidity: decoded.current.relativeHumidity,
                precipitation: decoded.current.precipitation,
                windSpeed: decoded.current.windSpeed,
                condition: currentDescriptor.title,
                symbolName: currentDescriptor.symbolName,
                unitSymbol: unit.symbol,
                windUnit: unit.windSpeedLabel,
                highTemperature: decoded.daily?.temperatureMax.first,
                lowTemperature: decoded.daily?.temperatureMin.first
            ),
            hourly: hourlySlice
        )
    }

    private func hourlyEntries(
        from hourly: OpenMeteoForecastResponse.Hourly,
        currentTime: String,
        unit: WeatherTemperatureUnit
    ) -> [WeatherSnapshot.HourlyEntry] {
        guard !hourly.time.isEmpty else { return [] }

        let startIndex = hourly.time.firstIndex(of: currentTime) ?? 0
        let endIndex = min(startIndex + 5, hourly.time.count)

        return (startIndex ..< endIndex).compactMap { index in
            guard index < hourly.temperature.count, index < hourly.weatherCode.count else { return nil }
            let isDay = hourly.isDay.flatMap { index < $0.count ? $0[index] : nil } ?? 1
            let descriptor = WeatherDescriptor.from(code: hourly.weatherCode[index], isDay: isDay == 1)
            return WeatherSnapshot.HourlyEntry(
                timeLabel: formattedHourLabel(from: hourly.time[index]),
                temperature: hourly.temperature[index],
                symbolName: descriptor.symbolName,
                unitSymbol: unit.symbol,
                precipitationProbability: hourly.precipitationProbability.flatMap { index < $0.count ? $0[index] : nil }
            )
        }
    }

    private func formattedHourLabel(from value: String) -> String {
        let raw = value.replacingOccurrences(of: "T", with: " ")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        guard let date = formatter.date(from: raw) else {
            return String(value.suffix(5))
        }

        let display = DateFormatter()
        display.locale = Locale.current
        display.dateFormat = "HH:mm"
        return display.string(from: date)
    }
}

@MainActor
final class QuickLaunchManager: ObservableObject {
    static let shared = QuickLaunchManager()

    @Published var lastError: String?

    private init() {}

    func open(_ item: QuickLaunchAppItem) {
        lastError = nil

        let standardizedPath = URL(fileURLWithPath: item.appPath).standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: standardizedPath) else {
            lastError = "\(item.displayName) is no longer available at \(standardizedPath)."
            return
        }

        let appURL = URL(fileURLWithPath: standardizedPath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                self?.lastError = error?.localizedDescription
            }
        }
    }
}

enum PomodoroPhase: String, CaseIterable, Identifiable {
    case focus = "Focus"
    case shortBreak = "Short Break"
    case longBreak = "Long Break"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .focus:
            return "brain.head.profile"
        case .shortBreak:
            return "cup.and.saucer.fill"
        case .longBreak:
            return "bed.double.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .focus:
            return "Focus"
        case .shortBreak:
            return "Short"
        case .longBreak:
            return "Long"
        }
    }
}

@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published private(set) var phase: PomodoroPhase = .focus
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var completedFocusSessions: Int = 0

    private var timerTask: Task<Void, Never>?
    private var targetDate: Date?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        remainingSeconds = Self.duration(for: .focus)

        Publishers.MergeMany([
            Defaults.publisher(.pomodoroEnabled).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.pomodoroFocusMinutes).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.pomodoroShortBreakMinutes).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.pomodoroLongBreakMinutes).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.pomodoroLongBreakInterval).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.pomodoroAutoStartNextPhase).map { _ in () }.eraseToAnyPublisher(),
        ])
        .sink { [weak self] _ in
            self?.handleConfigurationChange()
        }
        .store(in: &cancellables)
    }

    deinit {
        timerTask?.cancel()
    }

    var formattedRemaining: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var progress: Double {
        let total = max(phaseTotalSeconds, 1)
        return 1 - min(max(Double(remainingSeconds) / Double(total), 0), 1)
    }

    var phaseTotalSeconds: Int {
        Self.duration(for: phase)
    }

    var nextPhaseTitle: String {
        nextPhase(after: phase, completedFocusCount: phase == .focus ? completedFocusSessions + 1 : completedFocusSessions).rawValue
    }

    var currentCycleIndexLabel: String {
        let interval = max(2, Defaults[.pomodoroLongBreakInterval])
        let completedInCycle = completedFocusSessions % interval

        if phase == .focus {
            return "\(completedInCycle + 1)/\(interval)"
        }

        if completedFocusSessions > 0 && completedInCycle == 0 {
            return "\(interval)/\(interval)"
        }

        return "\(max(completedInCycle, 1))/\(interval)"
    }

    func toggleRunning() {
        isRunning ? pause() : start()
    }

    func start() {
        guard Defaults[.pomodoroEnabled] else { return }
        guard !isRunning else { return }

        if remainingSeconds <= 0 {
            remainingSeconds = phaseTotalSeconds
        }

        isRunning = true
        targetDate = Date().addingTimeInterval(Double(remainingSeconds))
        scheduleTickTask()
    }

    func pause() {
        guard isRunning else { return }
        syncRemainingToNow()
        stopTimer(clearRemaining: false)
    }

    func resetCurrentPhase() {
        stopTimer(clearRemaining: true)
    }

    func resetCycle() {
        completedFocusSessions = 0
        phase = .focus
        stopTimer(clearRemaining: true)
    }

    func skipPhase() {
        advanceToNextPhase(completedCurrentPhase: false, continueRunning: isRunning)
    }

    func selectPhase(_ newPhase: PomodoroPhase) {
        guard phase != newPhase else { return }
        phase = newPhase
        stopTimer(clearRemaining: true)
    }

    private func handleConfigurationChange() {
        guard Defaults[.pomodoroEnabled] else {
            resetCycle()
            return
        }

        if !isRunning {
            remainingSeconds = phaseTotalSeconds
        }
    }

    private func scheduleTickTask() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func tick() async {
        guard isRunning, let targetDate else { return }

        let nextRemaining = max(0, Int(ceil(targetDate.timeIntervalSinceNow)))
        if nextRemaining != remainingSeconds {
            remainingSeconds = nextRemaining
        }

        if nextRemaining <= 0 {
            completeCurrentPhase()
        }
    }

    private func completeCurrentPhase() {
        NSSound.beep()
        advanceToNextPhase(
            completedCurrentPhase: true,
            continueRunning: Defaults[.pomodoroAutoStartNextPhase]
        )
    }

    private func advanceToNextPhase(completedCurrentPhase: Bool, continueRunning: Bool) {
        let previousPhase = phase
        stopTimer(clearRemaining: false)

        if completedCurrentPhase && previousPhase == .focus {
            completedFocusSessions += 1
        }

        phase = nextPhase(
            after: previousPhase,
            completedFocusCount: completedFocusSessions
        )
        remainingSeconds = phaseTotalSeconds

        if continueRunning {
            start()
        }
    }

    private func nextPhase(after phase: PomodoroPhase, completedFocusCount: Int) -> PomodoroPhase {
        switch phase {
        case .focus:
            let interval = max(2, Defaults[.pomodoroLongBreakInterval])
            if completedFocusCount > 0 && completedFocusCount % interval == 0 {
                return .longBreak
            }
            return .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }

    private func syncRemainingToNow() {
        guard let targetDate else { return }
        remainingSeconds = max(0, Int(ceil(targetDate.timeIntervalSinceNow)))
    }

    private func stopTimer(clearRemaining: Bool) {
        isRunning = false
        targetDate = nil
        timerTask?.cancel()
        timerTask = nil

        if clearRemaining {
            remainingSeconds = phaseTotalSeconds
        }
    }

    private static func duration(for phase: PomodoroPhase) -> Int {
        let minutes: Int

        switch phase {
        case .focus:
            minutes = max(1, Defaults[.pomodoroFocusMinutes])
        case .shortBreak:
            minutes = max(1, Defaults[.pomodoroShortBreakMinutes])
        case .longBreak:
            minutes = max(1, Defaults[.pomodoroLongBreakMinutes])
        }

        return minutes * 60
    }
}

struct WeatherSnapshot {
    struct CurrentConditions {
        let temperature: Double
        let feelsLike: Double
        let humidity: Int
        let precipitation: Double
        let windSpeed: Double
        let condition: String
        let symbolName: String
        let unitSymbol: String
        let windUnit: String
        let highTemperature: Double?
        let lowTemperature: Double?
    }

    struct HourlyEntry: Identifiable {
        let id = UUID()
        let timeLabel: String
        let temperature: Double
        let symbolName: String
        let unitSymbol: String
        let precipitationProbability: Int?
    }

    let locationName: String
    let updatedAt: Date
    let current: CurrentConditions
    let hourly: [HourlyEntry]
}

enum WeatherDescriptor {
    case clear
    case clearNight
    case partlyCloudy
    case partlyCloudyNight
    case cloudy
    case fog
    case drizzle
    case rain
    case snow
    case thunder

    var title: String {
        switch self {
        case .clear: return "晴"
        case .clearNight: return "晴朗夜间"
        case .partlyCloudy: return "少云"
        case .partlyCloudyNight: return "少云夜间"
        case .cloudy: return "多云"
        case .fog: return "雾"
        case .drizzle: return "小雨"
        case .rain: return "雨"
        case .snow: return "雪"
        case .thunder: return "雷暴"
        }
    }

    var symbolName: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .clearNight: return "moon.stars.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .partlyCloudyNight: return "cloud.moon.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .thunder: return "cloud.bolt.rain.fill"
        }
    }

    static func from(code: Int, isDay: Bool) -> WeatherDescriptor {
        switch code {
        case 0:
            return isDay ? .clear : .clearNight
        case 1, 2:
            return isDay ? .partlyCloudy : .partlyCloudyNight
        case 3:
            return .cloudy
        case 45, 48:
            return .fog
        case 51, 53, 55, 56, 57:
            return .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return .rain
        case 71, 73, 75, 77, 85, 86:
            return .snow
        case 95, 96, 99:
            return .thunder
        default:
            return .cloudy
        }
    }
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String

        enum CodingKeys: String, CodingKey {
            case content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let plainText = try? container.decode(String.self, forKey: .content) {
                content = plainText
                return
            }

            if let array = try? container.decode([ContentPart].self, forKey: .content) {
                content = array.compactMap(\.text).joined(separator: "\n")
                return
            }

            content = ""
        }
    }

    struct ContentPart: Decodable {
        let text: String?
    }

    let choices: [Choice]
    let model: String?
}

private struct AIReply {
    let content: String
    let requestedModelName: String
    let resolvedModelName: String?
}

private struct AIServiceConfig {
    let endpoint: URL
    let apiKey: String
    let requestedModel: String
}

private struct AICalendarWriteAction: Decodable {
    let reply: String
    let createEvents: Bool
    let events: [AICalendarEventPayload]

    enum CodingKeys: String, CodingKey {
        case reply
        case createEvents = "create_events"
        case events
    }
}

private struct AICalendarEventPayload: Decodable {
    let title: String
    let start: String
    let end: String
    let notes: String?
    let location: String?
}

private struct OpenAIErrorResponse: Decodable {
    struct ErrorPayload: Decodable {
        let message: String?
    }

    let error: ErrorPayload
}

private struct GeocodingResponse: Decodable {
    struct ResultItem: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?

        var displayName: String {
            [name, admin1, country]
                .compactMap { component in
                    guard let component, !component.isEmpty else { return nil }
                    return component
                }
                .joined(separator: ", ")
        }
    }

    let results: [ResultItem]?
}

private extension String {
    var containsChineseCharacters: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x4E00 ... 0x9FFF, 0x3400 ... 0x4DBF, 0x20000 ... 0x2A6DF:
                return true
            default:
                return false
            }
        }
    }
}

private struct OpenMeteoForecastResponse: Decodable {
    struct Current: Decodable {
        let time: String
        let temperature: Double
        let relativeHumidity: Int
        let apparentTemperature: Double
        let precipitation: Double
        let weatherCode: Int
        let windSpeed: Double
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case relativeHumidity = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case precipitation
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
            case isDay = "is_day"
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature: [Double]
        let weatherCode: [Int]
        let precipitationProbability: [Int]?
        let isDay: [Int]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case precipitationProbability = "precipitation_probability"
            case isDay = "is_day"
        }
    }

    struct Daily: Decodable {
        let temperatureMax: [Double]
        let temperatureMin: [Double]

        enum CodingKeys: String, CodingKey {
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
        }
    }

    let current: Current
    let hourly: Hourly
    let daily: Daily?
}

private struct FeatureError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
