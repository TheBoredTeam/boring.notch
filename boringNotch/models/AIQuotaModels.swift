//
//  AIQuotaModels.swift
//  boringNotch
//

import Foundation

enum AIProvider: String, Codable, Equatable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    var iconName: String {
        switch self {
        case .claude: return "cloud.fill"
        case .codex: return "terminal.fill"
        }
    }
}

enum CredentialStatus: String, Codable, Equatable {
    case valid
    case expired
    case notFound = "not_found"
    case parseError = "parse_error"

    init(rawStatus: String?) {
        guard let rawStatus, let status = CredentialStatus(rawValue: rawStatus) else {
            self = .parseError
            return
        }
        self = status
    }
}

struct QuotaTier: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let utilization: Double
    let resetsAt: Date?

    init(id: UUID = UUID(), name: String, utilization: Double, resetsAt: Date?) {
        self.id = id
        self.name = name
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

struct ExtraUsage: Codable, Equatable {
    let isEnabled: Bool
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case currency
    }
}

struct AIQuotaResult: Codable, Equatable {
    let provider: AIProvider
    let credentialStatus: CredentialStatus
    let success: Bool
    let tiers: [QuotaTier]
    let extraUsage: ExtraUsage?
    let error: String?
    let queriedAt: Date?

    static func unavailable(
        provider: AIProvider,
        status: CredentialStatus,
        message: String?
    ) -> AIQuotaResult {
        AIQuotaResult(
            provider: provider,
            credentialStatus: status,
            success: false,
            tiers: [],
            extraUsage: nil,
            error: message,
            queriedAt: Date()
        )
    }
}

enum AIQuotaParser {
    static let knownClaudeTiers = [
        "five_hour",
        "seven_day",
        "seven_day_opus",
        "seven_day_sonnet",
    ]

    static func decodeClaudeQuota(from data: Data) throws -> AIQuotaResult {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any] else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Expected top-level object")
            )
        }

        var tiers: [QuotaTier] = []
        var seen = Set<String>()

        for tierName in knownClaudeTiers {
            if let tier = parseClaudeTier(named: tierName, value: object[tierName]) {
                tiers.append(tier)
                seen.insert(tierName)
            }
        }

        for key in object.keys.sorted() where key != "extra_usage" && !seen.contains(key) {
            if let tier = parseClaudeTier(named: key, value: object[key]) {
                tiers.append(tier)
            }
        }

        let extraUsage: ExtraUsage?
        if let extraObject = object["extra_usage"] {
            let extraData = try JSONSerialization.data(withJSONObject: extraObject)
            extraUsage = try JSONDecoder().decode(ExtraUsage.self, from: extraData)
        } else {
            extraUsage = nil
        }

        return AIQuotaResult(
            provider: .claude,
            credentialStatus: .valid,
            success: true,
            tiers: tiers,
            extraUsage: extraUsage,
            error: nil,
            queriedAt: Date()
        )
    }

    static func decodeCodexQuota(from data: Data) throws -> AIQuotaResult {
        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        let windows = [
            response.rateLimit?.primaryWindow,
            response.rateLimit?.secondaryWindow,
        ].compactMap { $0 }

        let tiers = windows.compactMap { window -> QuotaTier? in
            guard let usedPercent = window.usedPercent else { return nil }
            let name = window.limitWindowSeconds.map(tierName(forWindowSeconds:)) ?? "unknown"
            return QuotaTier(
                name: name,
                utilization: usedPercent,
                resetsAt: window.resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }

        return AIQuotaResult(
            provider: .codex,
            credentialStatus: .valid,
            success: true,
            tiers: tiers,
            extraUsage: nil,
            error: nil,
            queriedAt: Date()
        )
    }

    static func tierName(forWindowSeconds seconds: Int) -> String {
        switch seconds {
        case 18_000:
            return "five_hour"
        case 604_800:
            return "seven_day"
        default:
            let hours = seconds / 3_600
            if hours >= 24 {
                return "\(hours / 24)_day"
            }
            return "\(hours)_hour"
        }
    }

    static func parseDate(_ string: String) -> Date? {
        if let date = ISO8601DateFormatter.quotaWithFractionalSeconds.date(from: string) {
            return date
        }
        return ISO8601DateFormatter.quota.date(from: string)
    }

    private static func parseClaudeTier(named name: String, value: Any?) -> QuotaTier? {
        guard let object = value as? [String: Any] else { return nil }
        let utilization = object["utilization"] as? Double
            ?? (object["utilization"] as? NSNumber)?.doubleValue
        guard let utilization else { return nil }

        let resetsAt = (object["resets_at"] as? String).flatMap(parseDate)
        return QuotaTier(name: name, utilization: utilization, resetsAt: resetsAt)
    }
}

private extension ISO8601DateFormatter {
    static let quota: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let quotaWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct CodexUsageResponse: Decodable {
    let rateLimit: CodexRateLimit?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }
}

private struct CodexRateLimit: Decodable {
    let primaryWindow: CodexRateLimitWindow?
    let secondaryWindow: CodexRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Double?
    let limitWindowSeconds: Int?
    let resetAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }
}
