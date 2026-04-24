//
//  ClaudeUsageViewModel.swift
//  boringNotch
//
//  AI usage monitor — reads ~/.claude/usage-data.json
//

import Foundation
import Combine

enum UsageMeterKind {
    case used
    case remaining
}

struct UsageMeterDisplay: Identifiable {
    let id = UUID()
    let label: String
    let shortLabel: String
    let utilization: Int
    let resetsIn: String?
    let kind: UsageMeterKind
}

enum UsageAlertLevel: Int {
    case normal
    case warning
    case critical
}

struct UsageProviderDisplay: Identifiable {
    let id: String
    let name: String
    let iconName: String
    let planLabel: String?
    let creditsLabel: String?
    let statusText: String?
    let statusLevel: UsageAlertLevel
    let meters: [UsageMeterDisplay]
    let updatedAt: Date?
    let errorText: String?

    var primaryMeter: UsageMeterDisplay? { meters.first }
    var secondaryMeter: UsageMeterDisplay? { meters.dropFirst().first }
    var compactValueText: String {
        guard let primaryMeter else { return "--" }
        return "\(primaryMeter.utilization)%"
    }

    var compactResetText: String? { primaryMeter?.resetsIn }
}

@MainActor
class ClaudeUsageViewModel: ObservableObject {
    static let shared = ClaudeUsageViewModel()

    @Published var providers: [UsageProviderDisplay] = []
    @Published var isStale: Bool = true
    @Published var lastUpdated: Date?

    private var timer: Timer?
    private let filePath: URL

    var activeCompactProvider: UsageProviderDisplay? {
        providers.sorted {
            if $0.statusLevel != $1.statusLevel {
                return $0.statusLevel.rawValue > $1.statusLevel.rawValue
            }

            let lhsReset = resetSortValue(for: $0)
            let rhsReset = resetSortValue(for: $1)
            if lhsReset != rhsReset {
                return lhsReset < rhsReset
            }

            return $0.name < $1.name
        }.first
    }

    var activeCompactProviderID: String? {
        activeCompactProvider?.id
    }

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let realHome = URL(fileURLWithPath: NSHomeDirectory())
        let possiblePaths = [
            home.appendingPathComponent(".claude/usage-data.json"),
            realHome.appendingPathComponent(".claude/usage-data.json"),
            URL(fileURLWithPath: "/Users/\(NSUserName())/.claude/usage-data.json"),
        ]

        filePath = possiblePaths.first { FileManager.default.fileExists(atPath: $0.path) } ?? possiblePaths[0]

        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    func reload() {
        let exists = FileManager.default.fileExists(atPath: filePath.path)

        guard exists,
              let rawData = try? Data(contentsOf: filePath),
              let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] else {
            providers = []
            isStale = true
            lastUpdated = nil
            NSLog("[ClaudeUsage] Cannot read file (exists=%d, path=%@)", exists, filePath.path)
            return
        }

        if let timestampMs = jsonNumber(json["timestamp"]) {
            let age = Date().timeIntervalSince1970 - (timestampMs / 1000)
            isStale = age > 300
            lastUpdated = Date(timeIntervalSince1970: timestampMs / 1000)
        } else {
            isStale = true
            lastUpdated = nil
        }

        if let providersJSON = json["providers"] as? [String: Any] {
            providers = buildProviders(from: providersJSON)
        } else if let legacyProvider = buildLegacyClaudeProvider(from: json) {
            providers = [legacyProvider]
        } else {
            providers = []
        }

        NSLog("[ClaudeUsage] Loaded %d provider(s)", providers.count)
    }

    private func buildProviders(from providersJSON: [String: Any]) -> [UsageProviderDisplay] {
        let specs: [(key: String, fallbackName: String, iconName: String)] = [
            ("claude", "Claude", "claude-icon"),
            ("codex", "Codex", "openai-icon"),
        ]

        return specs.compactMap { spec in
            guard let providerJSON = providersJSON[spec.key] as? [String: Any] else {
                return nil
            }
            return buildProvider(
                from: providerJSON,
                id: spec.key,
                fallbackName: spec.fallbackName,
                iconName: spec.iconName
            )
        }
    }

    private func buildProvider(
        from providerJSON: [String: Any],
        id: String,
        fallbackName: String,
        iconName: String
    ) -> UsageProviderDisplay? {
        let auth = providerJSON["auth"] as? [String: Any]
        let limits = providerJSON["limits"] as? [String: Any]
        let providerTimestamp = jsonNumber(providerJSON["timestamp"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        let errorText = providerJSON["error"] as? String

        if let errorText {
            return UsageProviderDisplay(
                id: id,
                name: fallbackName,
                iconName: iconName,
                planLabel: planLabel(for: id, auth: auth),
                creditsLabel: nil,
                statusText: "Unavailable",
                statusLevel: .critical,
                meters: [],
                updatedAt: providerTimestamp,
                errorText: errorText
            )
        }

        guard let limits else { return nil }

        var meters: [UsageMeterDisplay] = []
        if id == "codex" {
            if let primary = buildCodexMeter(from: limits["primary"] as? [String: Any], label: "5h left", short: "5h") {
                meters.append(primary)
            }
            if let secondary = buildCodexMeter(from: limits["secondary"] as? [String: Any], label: "Weekly left", short: "7d") {
                meters.append(secondary)
            }
        } else {
            if let primary = buildClaudeMeter(from: limits["primary"] as? [String: Any], label: "Session used", short: "5h") {
                meters.append(primary)
            }
            if let secondary = buildClaudeMeter(from: limits["secondary"] as? [String: Any], label: "Weekly used", short: "7d") {
                meters.append(secondary)
            }
        }

        let creditsLabel = creditsLabel(from: limits["credits"] as? [String: Any])
        let statusText = statusText(for: id, limits: limits)
        let statusLevel = statusLevel(for: id, limits: limits)

        return UsageProviderDisplay(
            id: id,
            name: fallbackName,
            iconName: iconName,
            planLabel: planLabel(for: id, auth: auth),
            creditsLabel: creditsLabel,
            statusText: statusText,
            statusLevel: statusLevel,
            meters: meters,
            updatedAt: providerTimestamp,
            errorText: nil
        )
    }

    private func buildLegacyClaudeProvider(from json: [String: Any]) -> UsageProviderDisplay? {
        guard let limits = json["limits"] as? [String: Any] else {
            return nil
        }

        var meters: [UsageMeterDisplay] = []
        if let primary = buildLegacyClaudeMeter(from: limits["five_hour"] as? [String: Any], label: "Session used", short: "5h") {
            meters.append(primary)
        }
        if let secondary = buildLegacyClaudeMeter(from: limits["seven_day"] as? [String: Any], label: "Weekly used", short: "7d") {
            meters.append(secondary)
        }

        return UsageProviderDisplay(
            id: "claude",
            name: "Claude",
            iconName: "claude-icon",
            planLabel: nil,
            creditsLabel: nil,
            statusText: legacyClaudeStatusText(from: limits),
            statusLevel: legacyClaudeStatusLevel(from: limits),
            meters: meters,
            updatedAt: lastUpdated,
            errorText: json["error"] as? String
        )
    }

    private func buildClaudeMeter(from meterJSON: [String: Any]?, label: String, short: String) -> UsageMeterDisplay? {
        guard let meterJSON,
              let pct = jsonInt(meterJSON["utilization_pct"]) else {
            return nil
        }

        return UsageMeterDisplay(
            label: label,
            shortLabel: short,
            utilization: pct,
            resetsIn: resetText(from: meterJSON),
            kind: .used
        )
    }

    private func buildLegacyClaudeMeter(from meterJSON: [String: Any]?, label: String, short: String) -> UsageMeterDisplay? {
        guard let meterJSON,
              let pct = jsonInt(meterJSON["utilization_pct"]) else {
            return nil
        }

        return UsageMeterDisplay(
            label: label,
            shortLabel: short,
            utilization: pct,
            resetsIn: resetText(from: meterJSON),
            kind: .used
        )
    }

    private func buildCodexMeter(from meterJSON: [String: Any]?, label: String, short: String) -> UsageMeterDisplay? {
        guard let meterJSON,
              let usedPct = jsonInt(meterJSON["utilization_pct"]) else {
            return nil
        }

        let remainingPct = max(0, min(100, 100 - usedPct))

        return UsageMeterDisplay(
            label: label,
            shortLabel: short,
            utilization: remainingPct,
            resetsIn: resetText(from: meterJSON),
            kind: .remaining
        )
    }

    private func planLabel(for providerID: String, auth: [String: Any]?) -> String? {
        guard let auth else { return nil }

        if providerID == "codex" {
            guard let plan = auth["plan_type"] as? String, !plan.isEmpty else { return nil }
            return plan.prefix(1).uppercased() + plan.dropFirst()
        }

        let tier = auth["rate_limit_tier"] as? String
        let subscription = auth["subscription_type"] as? String
        let tierLabel = tier.flatMap(tierDisplay)

        if let tierLabel, let subscription, !subscription.isEmpty {
            return "\(tierLabel) (\(subscription.prefix(1).uppercased() + subscription.dropFirst()))"
        }

        return tierLabel
    }

    private func creditsLabel(from credits: [String: Any]?) -> String? {
        guard let credits else { return nil }

        if (credits["unlimited"] as? Bool) == true {
            return "Unlimited credits"
        }
        if (credits["has_credits"] as? Bool) == false {
            return "Credits depleted"
        }
        if let balance = credits["balance"] as? String, !balance.isEmpty {
            return "$\(balance) credits"
        }

        return nil
    }

    private func statusText(for providerID: String, limits: [String: Any]) -> String? {
        if providerID == "codex" {
            if let reachedType = limits["rate_limit_reached_type"] as? String, !reachedType.isEmpty {
                return humanizeStatus(reachedType)
            }
            return nil
        }

        if let status = limits["status"] as? String, status == "rejected" {
            return "Rate limited"
        }
        if let overage = limits["overage"] as? [String: Any],
           let overageStatus = overage["status"] as? String,
           overageStatus == "allowed_warning" {
            return "Overage warning"
        }
        if let status = limits["status"] as? String, status == "allowed_warning" {
            return "Approaching limit"
        }

        return nil
    }

    private func statusLevel(for providerID: String, limits: [String: Any]) -> UsageAlertLevel {
        if providerID == "codex" {
            if let reachedType = limits["rate_limit_reached_type"] as? String, !reachedType.isEmpty {
                return .critical
            }

            let remaining = jsonInt((limits["primary"] as? [String: Any])?["utilization_pct"]).map { 100 - $0 } ?? 100
            if remaining <= 10 { return .critical }
            if remaining <= 25 { return .warning }
            return .normal
        }

        if let status = limits["status"] as? String {
            switch status {
            case "rejected":
                return .critical
            case "allowed_warning":
                return .warning
            default:
                break
            }
        }

        if let overage = limits["overage"] as? [String: Any],
           let overageStatus = overage["status"] as? String {
            switch overageStatus {
            case "rejected":
                return .critical
            case "allowed_warning":
                return .warning
            default:
                break
            }
        }

        if let used = jsonInt((limits["primary"] as? [String: Any])?["utilization_pct"]) {
            if used >= 90 { return .critical }
            if used >= 75 { return .warning }
        }

        return .normal
    }

    private func legacyClaudeStatusText(from limits: [String: Any]) -> String? {
        if let status = limits["status"] as? String, status == "rejected" {
            return "Rate limited"
        }
        if let overage = limits["overage"] as? [String: Any],
           let overageStatus = overage["status"] as? String,
           overageStatus == "allowed_warning" {
            return "Overage warning"
        }
        if let status = limits["status"] as? String, status == "allowed_warning" {
            return "Approaching limit"
        }
        return nil
    }

    private func legacyClaudeStatusLevel(from limits: [String: Any]) -> UsageAlertLevel {
        if let status = limits["status"] as? String {
            switch status {
            case "rejected":
                return .critical
            case "allowed_warning":
                return .warning
            default:
                break
            }
        }

        if let used = jsonInt((limits["five_hour"] as? [String: Any])?["utilization_pct"]) {
            if used >= 90 { return .critical }
            if used >= 75 { return .warning }
        }

        return .normal
    }

    private func resetText(from meterJSON: [String: Any]) -> String? {
        if let epochSecs = jsonNumber(meterJSON["resets_at"]) {
            return formatDuration(Date(timeIntervalSince1970: epochSecs).timeIntervalSinceNow)
        }
        return formatResetTime(meterJSON["resets_at_iso"] as? String)
    }

    private func resetSortValue(for provider: UsageProviderDisplay) -> TimeInterval {
        guard let meter = provider.primaryMeter,
              let resetText = meter.resetsIn else {
            return .greatestFiniteMagnitude
        }

        return parseDuration(resetText)
    }

    private func tierDisplay(_ tier: String) -> String? {
        switch tier {
        case let value where value.contains("max_5x"):
            return "Max 5x"
        case let value where value.contains("max"):
            return "Max"
        case let value where value.contains("pro"):
            return "Pro"
        case let value where value.contains("default_raven"):
            return "Team (API)"
        case let value where value.contains("free"):
            return "Free"
        default:
            return tier.isEmpty ? nil : tier
        }
    }

    private func humanizeStatus(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func formatResetTime(_ isoString: String?) -> String? {
        guard let isoString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoString) else { return nil }
            return formatDuration(date.timeIntervalSinceNow)
        }
        return formatDuration(date.timeIntervalSinceNow)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String? {
        guard seconds > 0 else { return nil }
        let hrs = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        if hrs > 0 {
            return "\(hrs)h \(mins)m"
        }
        return "\(mins)m"
    }

    private func parseDuration(_ text: String) -> TimeInterval {
        let comps = text.split(separator: " ")
        var total: TimeInterval = 0

        for comp in comps {
            if comp.hasSuffix("h"), let hours = Double(comp.dropLast()) {
                total += hours * 3600
            } else if comp.hasSuffix("m"), let minutes = Double(comp.dropLast()) {
                total += minutes * 60
            }
        }

        return total > 0 ? total : .greatestFiniteMagnitude
    }

    private func jsonInt(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let double as Double:
            return Int(double)
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private func jsonNumber(_ value: Any?) -> Double? {
        switch value {
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case let int64 as Int64:
            return Double(int64)
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }
}
