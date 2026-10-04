//
//  ReelsManager.swift
//  boringNotch
//
//  Short-form-video ("reels") counter + soft blocker. Polls the frontmost
//  browser's active tab URL via AppleScript; when it's an Instagram Reels or
//  YouTube Shorts feed it accumulates watch time, nudges you, and — once you
//  pass a daily limit — redirects the tab away.
//
//  Limits (honest): browser-only (native apps/PWAs can't be read this way),
//  time-based rather than per-reel, and the block redirects the whole tab
//  rather than hiding just the feed. Reading/controlling browsers prompts for
//  macOS Automation permission the first time.
//

import AppKit
import Combine
import Defaults
import Foundation
import UserNotifications

// Per-day reels record, persisted via Defaults.
struct ReelsDayStat: Codable, Defaults.Serializable {
    var seconds: Double
    var opens: Int
    var count: Int   // number of distinct reels/shorts scrolled through

    init(seconds: Double, opens: Int, count: Int) {
        self.seconds = seconds
        self.opens = opens
        self.count = count
    }

    // Tolerant decode so records written before `count` existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        opens = try c.decodeIfPresent(Int.self, forKey: .opens) ?? 0
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }
}

@MainActor
final class ReelsManager: ObservableObject {
    static let shared = ReelsManager()

    @Published private(set) var isOnReels = false
    @Published private(set) var isOverLimit = false
    @Published private(set) var currentPlatform: String? = nil
    @Published private(set) var todaySeconds: Double = 0
    @Published private(set) var todayOpens: Int = 0
    @Published private(set) var todayCount: Int = 0

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastTick: Date?
    private var wasOnReels = false
    private var lastReelID: String?
    private var currentDayKey = ""
    private var lastNudge: Date = .distantPast
    private var lastRedirect: Date = .distantPast

    // Browsers we know how to script. `isSafari` selects the Safari tab idiom
    // ("current tab") vs the Chromium idiom ("active tab").
    private let browsers: [(bundle: String, name: String, isSafari: Bool)] = [
        ("com.google.Chrome", "Google Chrome", false),
        ("com.apple.Safari", "Safari", true),
        ("com.openai.atlas", "ChatGPT Atlas", false),
        ("company.thebrowser.Browser", "Arc", false),
        ("com.brave.Browser", "Brave Browser", false),
        ("com.microsoft.edgemac", "Microsoft Edge", false)
    ]

    private init() {
        currentDayKey = Self.dayKey()
        loadToday()
        // Start/stop polling as the feature is toggled.
        Defaults.publisher(.reelsBlockerEnabled)
            .sink { [weak self] _ in Task { @MainActor in self?.updateMonitoring() } }
            .store(in: &cancellables)
        updateMonitoring()
    }

    // MARK: - Monitoring lifecycle

    private func updateMonitoring() {
        if Defaults[.reelsBlockerEnabled] {
            guard timer == nil else { return }
            let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.poll() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            timer?.invalidate()
            timer = nil
            lastTick = nil
            isOnReels = false
            currentPlatform = nil
        }
    }

    // MARK: - Poll

    private func poll() async {
        guard Defaults[.reelsBlockerEnabled] else { return }
        rolloverIfNeeded()

        let now = Date()
        let browser = frontmostBrowser()
        var platform: String? = nil
        var reelID: String? = nil
        if let b = browser, let url = await activeTabURL(for: b) {
            platform = self.platform(for: url)
            if platform != nil { reelID = self.reelID(from: url) }
        }
        let onReels = platform != nil

        let delta = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now

        if onReels {
            // Ignore implausibly large gaps (machine slept) so a nap doesn't
            // register as hours of scrolling.
            if delta > 0, delta < 10 { todaySeconds += delta }
            if !wasOnReels { todayOpens += 1 }
            // Count a reel each time the URL's reel/short id changes to a new one
            // (e.g. swiping to the next Short bumps the video id).
            if let id = reelID, id != lastReelID {
                lastReelID = id
                todayCount += 1
            }
            currentPlatform = platform
            isOnReels = true

            let limitSec = Double(Defaults[.reelsDailyLimitMinutes]) * 60
            let over = limitSec > 0 && todaySeconds >= limitSec
            isOverLimit = over

            if over, Defaults[.reelsAutoRedirect], let b = browser {
                await redirect(b)
                notify(title: "Reel limit reached",
                       body: "You've hit your \(Defaults[.reelsDailyLimitMinutes])-min daily limit. Closing the feed.",
                       throttle: 15)
            } else if !wasOnReels {
                notify(title: "Watching \(platform ?? "Reels")", body: nudgeBody(), throttle: 0)
            } else {
                notify(title: platform ?? "Reels", body: nudgeBody(), throttle: 300)
            }
            saveToday()
        } else {
            isOnReels = false
            isOverLimit = false
            currentPlatform = nil
        }
        wasOnReels = onReels
    }

    private func nudgeBody() -> String {
        let mins = Int(todaySeconds / 60)
        return "\(todayCount) reels · \(mins)m today"
    }

    /// Extracts a stable per-reel identifier from the URL (case-preserved, since
    /// YouTube ids are case-sensitive). Returns nil for feed pages without an id.
    private func reelID(from url: String) -> String? {
        let lower = url.lowercased()
        func idAfter(_ marker: String, tag: String) -> String? {
            guard let r = lower.range(of: marker) else { return nil }
            // Lowercasing ASCII preserves length, so the offset maps back cleanly.
            let offset = lower.distance(from: lower.startIndex, to: r.upperBound)
            guard offset <= url.count else { return nil }
            let start = url.index(url.startIndex, offsetBy: offset)
            let id = url[start...].prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            return id.isEmpty ? nil : tag + String(id)
        }
        return idAfter("/shorts/", tag: "yt:")
            ?? idAfter("/reel/", tag: "ig:")
            ?? idAfter("/reels/", tag: "ig:")
    }

    // MARK: - Browser scripting

    private func frontmostBrowser() -> (bundle: String, name: String, isSafari: Bool)? {
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        return browsers.first { $0.bundle == front }
    }

    private func activeTabURL(for browser: (bundle: String, name: String, isSafari: Bool)) async -> String? {
        let prop = browser.isSafari ? "URL of current tab of front window"
                                    : "URL of active tab of front window"
        let script = "tell application \"\(browser.name)\" to return \(prop)"
        do {
            let desc = try await AppleScriptHelper.execute(script)
            return desc?.stringValue
        } catch {
            return nil
        }
    }

    private func redirect(_ browser: (bundle: String, name: String, isSafari: Bool)) async {
        // Throttle so we don't fight the user every single tick.
        guard Date().timeIntervalSince(lastRedirect) > 4 else { return }
        lastRedirect = Date()
        let prop = browser.isSafari ? "URL of current tab of front window"
                                    : "URL of active tab of front window"
        let script = "tell application \"\(browser.name)\" to set \(prop) to \"about:blank\""
        try? await AppleScriptHelper.executeVoid(script)
    }

    /// Returns the matched platform label, or nil if the URL isn't a tracked feed.
    private func platform(for url: String) -> String? {
        let u = url.lowercased()
        if Defaults[.reelsTrackInstagram], u.contains("instagram.com/reel") { return "Instagram Reels" }
        if Defaults[.reelsTrackYouTube], u.contains("youtube.com/shorts") { return "YouTube Shorts" }
        return nil
    }

    // MARK: - Notifications

    private func notify(title: String, body: String, throttle: TimeInterval) {
        if throttle > 0, Date().timeIntervalSince(lastNudge) < throttle { return }
        lastNudge = Date()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Stats / persistence

    private static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func rolloverIfNeeded() {
        let key = Self.dayKey()
        guard key != currentDayKey else { return }
        currentDayKey = key
        loadToday()
        wasOnReels = false
        lastReelID = nil
    }

    private func loadToday() {
        let stat = Defaults[.reelsStats][currentDayKey] ?? ReelsDayStat(seconds: 0, opens: 0, count: 0)
        todaySeconds = stat.seconds
        todayOpens = stat.opens
        todayCount = stat.count
        isOverLimit = false
    }

    private func saveToday() {
        var stats = Defaults[.reelsStats]
        stats[currentDayKey] = ReelsDayStat(seconds: todaySeconds, opens: todayOpens, count: todayCount)
        // Keep the map small — only the trailing 30 days.
        if stats.count > 40 {
            let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -30, to: Date())!
            let cutoffKey = Self.dayKey(cutoff)
            stats = stats.filter { $0.key >= cutoffKey }
        }
        Defaults[.reelsStats] = stats
    }

    func weekSeconds() -> Double {
        let stats = Defaults[.reelsStats]
        let cal = Calendar(identifier: .gregorian)
        return (0..<7).reduce(0.0) { sum, off in
            guard let d = cal.date(byAdding: .day, value: -off, to: Date()) else { return sum }
            return sum + (stats[Self.dayKey(d)]?.seconds ?? 0)
        }
    }

    func weekCount() -> Int {
        let stats = Defaults[.reelsStats]
        let cal = Calendar(identifier: .gregorian)
        return (0..<7).reduce(0) { sum, off in
            guard let d = cal.date(byAdding: .day, value: -off, to: Date()) else { return sum }
            return sum + (stats[Self.dayKey(d)]?.count ?? 0)
        }
    }

    func resetStats() {
        Defaults[.reelsStats] = [:]
        todaySeconds = 0
        todayOpens = 0
        todayCount = 0
        lastReelID = nil
        isOverLimit = false
    }
}
