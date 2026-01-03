//
//  ClaudeCodeModels.swift
//  boringNotch
//
//  Created for Claude Code Notch integration
//

import Foundation

// MARK: - Session Discovery

/// Represents an active Claude Code IDE session from ~/.claude/ide/*.lock
struct ClaudeSession: Identifiable, Codable, Equatable {
    // Use workspace path as unique ID since multiple sessions can share the same PID (Cursor)
    var id: String { workspaceFolders.first ?? "\(pid)" }

    let pid: Int
    let workspaceFolders: [String]
    let ideName: String
    let transport: String?
    let runningInWindows: Bool?

    /// Derived from workspace path for project JSONL lookup
    var projectKey: String? {
        guard let workspace = workspaceFolders.first else { return nil }
        // Convert /Users/foo/bar.baz to -Users-foo-bar-baz
        // Claude Code keeps the leading dash, so we only trim trailing dashes
        return workspace
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    /// Display name for UI (last folder component)
    var displayName: String {
        guard let workspace = workspaceFolders.first else { return "Unknown" }
        return URL(fileURLWithPath: workspace).lastPathComponent
    }
}

// MARK: - Token Usage

/// Token usage data from JSONL message.usage field
struct TokenUsage: Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadInputTokens: Int = 0
    var cacheCreationInputTokens: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens
    }

    /// Context window is 200k for opus-4-5
    static let contextWindow = 200_000

    var contextPercentage: Double {
        guard Self.contextWindow > 0 else { return 0 }
        return min(100, Double(totalTokens) / Double(Self.contextWindow) * 100)
    }

    // MARK: - Cost Estimation (per 1M tokens, USD)
    // Opus 4.5 pricing: $15/1M input, $75/1M output, $1.50/1M cache read, $18.75/1M cache write
    // Sonnet 4: $3/1M input, $15/1M output, $0.30/1M cache read, $3.75/1M cache write

    struct ModelPricing {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cacheReadPerMillion: Double
        let cacheWritePerMillion: Double
    }

    static let opusPricing = ModelPricing(
        inputPerMillion: 15.0,
        outputPerMillion: 75.0,
        cacheReadPerMillion: 1.50,
        cacheWritePerMillion: 18.75
    )

    static let sonnetPricing = ModelPricing(
        inputPerMillion: 3.0,
        outputPerMillion: 15.0,
        cacheReadPerMillion: 0.30,
        cacheWritePerMillion: 3.75
    )

    /// Calculate estimated cost for this session
    func estimatedCost(model: String) -> Double {
        let pricing = model.contains("opus") ? Self.opusPricing : Self.sonnetPricing

        let inputCost = Double(inputTokens) / 1_000_000 * pricing.inputPerMillion
        let outputCost = Double(outputTokens) / 1_000_000 * pricing.outputPerMillion
        let cacheReadCost = Double(cacheReadInputTokens) / 1_000_000 * pricing.cacheReadPerMillion
        let cacheWriteCost = Double(cacheCreationInputTokens) / 1_000_000 * pricing.cacheWritePerMillion

        return inputCost + outputCost + cacheReadCost + cacheWriteCost
    }
}

// MARK: - Tool Execution

/// Represents a tool call in progress or completed
struct ToolExecution: Identifiable, Equatable {
    let id: String
    let toolName: String
    let argument: String?
    let startTime: Date
    var endTime: Date?
    var isRunning: Bool { endTime == nil }

    var durationMs: Int? {
        guard let end = endTime else { return nil }
        return Int(end.timeIntervalSince(startTime) * 1000)
    }
}

// MARK: - Agent Info

/// Represents a background agent task
struct AgentInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let startTime: Date
    var isActive: Bool = true

    var durationSeconds: Int {
        Int(Date().timeIntervalSince(startTime))
    }
}

// MARK: - Todo Item

/// Claude Code todo item
struct ClaudeTodoItem: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let status: TodoStatus

    enum TodoStatus: String {
        case pending
        case inProgress = "in_progress"
        case completed
    }
}

// MARK: - Complete State

/// Complete Claude Code state for display
struct ClaudeCodeState: Equatable {
    var sessionId: String = ""
    var model: String = ""
    var cwd: String = ""
    var gitBranch: String = ""

    var tokenUsage: TokenUsage = TokenUsage()

    var lastMessage: String = ""
    var lastMessageTime: Date?

    var activeTools: [ToolExecution] = []
    var recentTools: [ToolExecution] = []

    var agents: [AgentInfo] = []
    var todos: [ClaudeTodoItem] = []

    var isConnected: Bool = false
    var lastUpdateTime: Date?

    /// True when Claude is waiting for user permission to execute a tool
    var needsPermission: Bool = false
    /// The tool waiting for permission (if any)
    var pendingPermissionTool: String?

    /// True when Claude is actively generating a response (thinking)
    var isThinking: Bool = false

    // Convenience accessors
    var contextPercentage: Double { tokenUsage.contextPercentage }
    var hasActiveTools: Bool { !activeTools.isEmpty }
    var currentToolName: String? { activeTools.first?.toolName }

    /// True when the session is actively processing (thinking or running tools)
    var isActive: Bool { isThinking || hasActiveTools }
}

// MARK: - Daily Stats (from stats-cache.json)

/// Daily activity stats from ~/.claude/stats-cache.json
struct DailyStats: Equatable {
    var messageCount: Int = 0
    var toolCallCount: Int = 0
    var sessionCount: Int = 0
    var tokensUsed: Int = 0
    var date: String = ""

    var isEmpty: Bool {
        // Only empty if date is not set (means we haven't loaded stats yet)
        date.isEmpty
    }
}

/// Stats cache structure matching ~/.claude/stats-cache.json
struct StatsCache: Codable {
    let dailyActivity: [DailyActivity]?
    let dailyModelTokens: [DailyModelTokens]?
    let modelUsage: [String: ModelUsageStats]?
    let totalSessions: Int?
    let totalMessages: Int?

    struct DailyActivity: Codable {
        let date: String
        let messageCount: Int?
        let sessionCount: Int?
        let toolCallCount: Int?
    }

    struct DailyModelTokens: Codable {
        let date: String
        let tokensByModel: [String: Int]?
    }

    struct ModelUsageStats: Codable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?
    }
}

// MARK: - JSONL Parsing Helpers

/// Represents a parsed JSONL line from session log
struct SessionLogEntry {
    let type: String
    let sessionId: String?
    let model: String?
    let cwd: String?
    let gitBranch: String?
    let usage: TokenUsage?
    let messageContent: String?
    let toolUse: ToolUseInfo?
    let toolResult: ToolResultInfo?
    let timestamp: Date?
}

struct ToolUseInfo {
    let id: String
    let name: String
    let input: [String: Any]?
}

struct ToolResultInfo {
    let toolUseId: String
    let content: String?
    let isError: Bool
}
