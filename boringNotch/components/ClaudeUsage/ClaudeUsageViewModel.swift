//
//  ClaudeUsageViewModel.swift
//  boringNotch
//
//  Claude usage monitor — reads ~/.claude/usage-data.json
//

import Foundation
import Combine

// Using manual JSON parsing instead of Codable to handle unknown keys gracefully

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
        // Try multiple paths - sandbox may remap home directory
        let home = FileManager.default.homeDirectoryForCurrentUser
        let realHome = URL(fileURLWithPath: NSHomeDirectory())
        let possiblePaths = [
            home.appendingPathComponent(".claude/usage-data.json"),
            realHome.appendingPathComponent(".claude/usage-data.json"),
            URL(fileURLWithPath: "/Users/\(NSUserName())/.claude/usage-data.json"),
        ]

        // Use the first path that exists, or default to the first
        filePath = possiblePaths.first { FileManager.default.fileExists(atPath: $0.path) }
            ?? possiblePaths[0]

        NSLog("[ClaudeUsage] Using path: %@", filePath.path)
        NSLog("[ClaudeUsage] File exists: %d", FileManager.default.fileExists(atPath: filePath.path))

        // Write breadcrumb to prove we ran
        let breadcrumb = "init at \(Date()) path=\(filePath.path) exists=\(FileManager.default.fileExists(atPath: filePath.path))\n"
        try? breadcrumb.write(to: URL(fileURLWithPath: "/tmp/claude-usage-debug.txt"), atomically: true, encoding: .utf8)

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
            NSLog("[ClaudeUsage] Cannot read file (exists=%d, path=%@)", exists, filePath.path)
            isStale = true
            return
        }

        // Check freshness
        if let ts = json["timestamp"] as? Double {
            let age = Date().timeIntervalSince1970 - (ts / 1000)
            isStale = age > 300
            lastUpdated = Date(timeIntervalSince1970: ts / 1000)
        }

        // Navigate to settings_usage.data
        guard let settingsUsage = json["settings_usage"] as? [String: Any],
              let usageData = settingsUsage["data"] as? [String: Any] else {
            NSLog("[ClaudeUsage] No settings_usage.data in JSON")
            return
        }

        var newMeters: [UsageMeterDisplay] = []

        let meterDefs: [(key: String, label: String, short: String)] = [
            ("five_hour", "Session (5h)", "5h"),
            ("seven_day", "Weekly", "7d"),
            ("seven_day_sonnet", "Sonnet", "Son"),
            ("seven_day_opus", "Opus", "Op"),
        ]

        for def in meterDefs {
            if let m = usageData[def.key] as? [String: Any],
               let pct = m["utilization"] as? Int {
                if def.key == "five_hour" { sessionPct = pct }
                if def.key == "seven_day" { weeklyPct = pct }
                newMeters.append(UsageMeterDisplay(
                    label: def.label,
                    shortLabel: def.short,
                    utilization: pct,
                    resetsIn: formatResetTime(m["resets_at"] as? String)
                ))
            }
        }

        meters = newMeters

        if let extra = usageData["extra_usage"] as? [String: Any] {
            extraUsageEnabled = extra["is_enabled"] as? Bool ?? false
            extraUsageCredits = Double(extra["used_credits"] as? Int ?? 0) / 100.0
        }

        NSLog("[ClaudeUsage] Loaded %d meters, session=%d%%", newMeters.count, sessionPct)
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
