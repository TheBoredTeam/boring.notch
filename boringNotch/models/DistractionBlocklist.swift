//
//  DistractionBlocklist.swift
//  boringNotch
//
//  What counts as a distraction while a focus session is running.
//
//  Host matching is the part worth being careful about: a blocklist that
//  matches by substring blocks `notreddit.com` and `reddit.com.example.org`
//  along with `reddit.com`, and one that only matches exactly misses
//  `www.reddit.com` and `old.reddit.com`. This file does label-boundary
//  matching, the same rule `MeetingProvider.provider(forHost:)` already uses
//  for meeting links, and it is covered by tests on both sides of that line.
//

import Foundation

/// A site the user wants blocked, stored as a bare registrable host.
struct BlockedSite: Hashable, Identifiable, Sendable {
    let host: String

    var id: String { host }

    /// Accepts whatever the user typed — "reddit.com", "www.reddit.com",
    /// "https://reddit.com/r/all", "  Reddit.com/  " — and reduces it to a
    /// comparable host. Returns nil when there is no host to speak of.
    init?(userInput: String) {
        var text = userInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }

        // Strip a scheme so URLComponents doesn't treat "reddit.com/r/all" as
        // a relative path, then re-add one to parse uniformly.
        if let range = text.range(of: "://") {
            text = String(text[range.upperBound...])
        }
        // Drop credentials, path, query and fragment.
        if let at = text.firstIndex(of: "@") {
            text = String(text[text.index(after: at)...])
        }
        text = text.components(separatedBy: CharacterSet(charactersIn: "/?#")).first ?? text
        // Drop a port.
        text = text.components(separatedBy: ":").first ?? text
        // A leading "www." is noise: blocking reddit.com should block
        // www.reddit.com anyway, and storing both would look like a bug.
        if text.hasPrefix("www.") {
            text = String(text.dropFirst(4))
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard !text.isEmpty, text.contains("."), !text.contains(" ") else { return nil }
        self.host = text
    }

    /// Trusted initialiser for values already known to be normalised
    /// (defaults, decoded preferences, tests).
    init(host: String) {
        self.host = host.lowercased()
    }

    /// True when `candidate` is this host or a subdomain of it.
    ///
    /// The boundary check is what keeps "notreddit.com" out: a suffix match
    /// alone would accept it, so the character before the suffix must be a
    /// label separator.
    func matches(host candidate: String) -> Bool {
        let candidate = candidate.lowercased()
        if candidate == host { return true }
        return candidate.hasSuffix("." + host)
    }

    /// True when the URL's host is this site or a subdomain of it.
    func matches(url: URL) -> Bool {
        guard let candidate = url.host else { return false }
        return matches(host: candidate)
    }
}

/// An app the user wants blocked while focusing.
struct BlockedApp: Hashable, Identifiable, Sendable {
    let bundleID: String
    var id: String { bundleID }
}

/// The full set of things to block, plus the matching rules.
struct DistractionBlocklist: Equatable, Sendable {
    var apps: Set<BlockedApp>
    var sites: Set<BlockedSite>
    var blockApps: Bool
    var blockSites: Bool

    init(
        apps: Set<BlockedApp> = [],
        sites: Set<BlockedSite> = [],
        blockApps: Bool = false,
        blockSites: Bool = false
    ) {
        self.apps = apps
        self.sites = sites
        self.blockApps = blockApps
        self.blockSites = blockSites
    }

    var isEmpty: Bool {
        (!blockApps || apps.isEmpty) && (!blockSites || sites.isEmpty)
    }

    /// Whether an app that just came to the front should be pushed back.
    ///
    /// Browsers are never blocked as apps even if listed: hiding Safari
    /// because one tab is Reddit takes away the user's whole browser. Sites
    /// are handled by the site rule instead, which acts on the tab.
    func shouldBlockApp(bundleID: String) -> Bool {
        guard blockApps else { return false }
        let normalized = normalizeBundleIdentifier(bundleID)
        guard !Self.browserBundleIDs.contains(normalized.lowercased()) else { return false }
        return apps.contains(BlockedApp(bundleID: normalized))
    }

    func shouldBlockSite(url: URL) -> Bool {
        guard blockSites else { return false }
        // Only ordinary web traffic. A blocklist entry must never cause the
        // app to navigate away from a file:// or about: page.
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return sites.contains { $0.matches(url: url) }
    }

    func shouldBlockSite(urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return shouldBlockSite(url: url)
    }

    /// Browsers whose *tabs* are checked rather than the app being hidden.
    /// Matched case-insensitively against a normalized bundle ID.
    static let browserBundleIDs: Set<String> = [
        "com.apple.safari",
        "com.apple.safaritechnologypreview",
        "com.google.chrome",
        "com.google.chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.browser",
        "company.thebrowser.browser",
        "org.mozilla.firefox",
        "com.vivaldi.vivaldi",
        "com.operasoftware.opera"
    ]

    /// The sites offered as one-tap suggestions in settings — the four named
    /// in the feature request, plus the handful most often asked for with them.
    static let suggestedSites: [BlockedSite] = [
        BlockedSite(host: "instagram.com"),
        BlockedSite(host: "reddit.com"),
        BlockedSite(host: "youtube.com"),
        BlockedSite(host: "x.com"),
        BlockedSite(host: "twitter.com"),
        BlockedSite(host: "facebook.com"),
        BlockedSite(host: "tiktok.com"),
        BlockedSite(host: "news.ycombinator.com")
    ]

    static let suggestedApps: [BlockedApp] = [
        BlockedApp(bundleID: "com.hnc.Discord"),
        BlockedApp(bundleID: "com.tinyspeck.slackmacgap"),
        BlockedApp(bundleID: "ru.keepcoder.Telegram"),
        BlockedApp(bundleID: "net.whatsapp.WhatsApp"),
        BlockedApp(bundleID: "com.apple.MobileSMS"),
        BlockedApp(bundleID: "com.valvesoftware.steam")
    ]
}
