//
//  ClaudeUsageViewModel.swift
//  boringNotch
//
//  Claude usage monitor — reads ~/.claude/usage-data.json
//

import Foundation
import Combine

struct UsageMeter: Codable {
    let utilization: Int?
    let resets_at: String?
}

struct ExtraUsage: Codable {
    let is_enabled: Bool?
    let monthly_limit: Int?
    let used_credits: Int?
    let utilization: Int?
}

struct UsageData: Codable {
    let five_hour: UsageMeter?
    let seven_day: UsageMeter?
    let seven_day_oauth_apps: UsageMeter?
    let seven_day_opus: UsageMeter?
    let seven_day_sonnet: UsageMeter?
    let seven_day_cowork: UsageMeter?
    let extra_usage: ExtraUsage?
}

struct UsageAccount: Codable {
    let name: String?
    let email: String?
}

struct UsageOrganization: Codable {
    let name: String?
    let rate_limit_tier: String?
}

struct SettingsUsage: Codable {
    let data: UsageData?
}

struct ClaudeUsageFile: Codable {
    let timestamp: Double?
    let account: UsageAccount?
    let organization: UsageOrganization?
    let settings_usage: SettingsUsage?
}

struct UsageMeterDisplay: Identifiable {
    let id = UUID()
    let label: String
    let shortLabel: String
    let utilization: Int
    let resetsIn: String?
}

@MainActor
class ClaudeUsageViewModel: ObservableObject {
    static let shared = ClaudeUsageViewModel()

    @Published var meters: [UsageMeterDisplay] = []
    @Published var sessionPct: Int = 0
    @Published var weeklyPct: Int = 0
    @Published var extraUsageEnabled: Bool = false
    @Published var extraUsageCredits: Double = 0
    @Published var isStale: Bool = true
    @Published var lastUpdated: Date?

    private var timer: Timer?
    private let filePath: URL

    private init() {
        filePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/usage-data.json")
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    func reload() {
        guard let data = try? Data(contentsOf: filePath),
              let file = try? JSONDecoder().decode(ClaudeUsageFile.self, from: data) else {
            isStale = true
            return
        }

        // Check freshness
        if let ts = file.timestamp {
            let age = Date().timeIntervalSince1970 - (ts / 1000)
            isStale = age > 300 // 5 minutes
            lastUpdated = Date(timeIntervalSince1970: ts / 1000)
        }

        guard let usage = file.settings_usage?.data else { return }

        var newMeters: [UsageMeterDisplay] = []

        if let m = usage.five_hour, let pct = m.utilization {
            sessionPct = pct
            newMeters.append(UsageMeterDisplay(
                label: "Session (5h)",
                shortLabel: "5h",
                utilization: pct,
                resetsIn: formatResetTime(m.resets_at)
            ))
        }

        if let m = usage.seven_day, let pct = m.utilization {
            weeklyPct = pct
            newMeters.append(UsageMeterDisplay(
                label: "Weekly",
                shortLabel: "7d",
                utilization: pct,
                resetsIn: formatResetTime(m.resets_at)
            ))
        }

        if let m = usage.seven_day_sonnet, let pct = m.utilization {
            newMeters.append(UsageMeterDisplay(
                label: "Sonnet",
                shortLabel: "Son",
                utilization: pct,
                resetsIn: formatResetTime(m.resets_at)
            ))
        }

        if let m = usage.seven_day_opus, let pct = m.utilization {
            newMeters.append(UsageMeterDisplay(
                label: "Opus",
                shortLabel: "Op",
                utilization: pct,
                resetsIn: formatResetTime(m.resets_at)
            ))
        }

        meters = newMeters

        if let extra = usage.extra_usage {
            extraUsageEnabled = extra.is_enabled ?? false
            extraUsageCredits = Double(extra.used_credits ?? 0) / 100.0
        }
    }

    private func formatResetTime(_ isoString: String?) -> String? {
        guard let isoString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            // Try without fractional seconds
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
}
