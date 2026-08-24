//
//  CategoryResolver.swift
//  boringNotch
//
//  Pure, Foundation-only mapping from an app bundle ID to an `AppCategory`.
//  Ships a curated default map; user overrides (loaded from Defaults by the manager)
//  take precedence. Free of AppKit/SwiftUI so it can be unit-tested with the swift CLI.
//

import Foundation

struct CategoryResolver {
    /// All known categories, including `.other` as the fallback.
    let categories: [AppCategory]
    /// bundleID -> categoryID (built-in defaults).
    let defaultMap: [String: String]
    /// bundleID prefix -> categoryID, checked after exact matches (e.g. JetBrains, Adobe).
    let prefixRules: [(prefix: String, categoryID: String)]
    /// bundleID -> categoryID, user-assigned. Wins over defaults.
    let overrides: [String: String]

    private let categoriesByID: [String: AppCategory]

    init(
        categories: [AppCategory] = CategoryResolver.defaultCategories,
        defaultMap: [String: String] = CategoryResolver.defaultBundleMap,
        prefixRules: [(prefix: String, categoryID: String)] = CategoryResolver.defaultPrefixRules,
        overrides: [String: String] = [:]
    ) {
        self.categories = categories
        self.defaultMap = defaultMap
        self.prefixRules = prefixRules
        self.overrides = overrides
        self.categoriesByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Resolve a bundle ID to a category. Never nil — falls back to `.other`.
    /// Order: user override → exact default → prefix rule → `.other`.
    func category(for bundleID: String) -> AppCategory {
        if let id = overrides[bundleID], let cat = categoriesByID[id] { return cat }
        if let id = defaultMap[bundleID], let cat = categoriesByID[id] { return cat }
        if let rule = prefixRules.first(where: { bundleID.hasPrefix($0.prefix) }),
           let cat = categoriesByID[rule.categoryID] { return cat }
        return Self.other
    }
}

// MARK: - Defaults

extension CategoryResolver {
    static let other = AppCategory(id: "other", name: "Other", colorHex: "#48484A")

    static let defaultCategories: [AppCategory] = [
        AppCategory(id: "development",   name: "Development",   colorHex: "#5E9EFF"),
        AppCategory(id: "communication", name: "Communication", colorHex: "#34C759"),
        AppCategory(id: "social",        name: "Social",        colorHex: "#FF375F"),
        AppCategory(id: "browsing",      name: "Browsing",      colorHex: "#FF9F0A"),
        AppCategory(id: "entertainment", name: "Entertainment", colorHex: "#BF5AF2"),
        AppCategory(id: "productivity",  name: "Productivity",  colorHex: "#64D2FF"),
        AppCategory(id: "design",        name: "Design",        colorHex: "#FF6482"),
        AppCategory(id: "utilities",     name: "Utilities",     colorHex: "#8E8E93"),
        other,
    ]

    static let defaultBundleMap: [String: String] = [
        // Development
        "com.apple.dt.Xcode": "development",
        "com.microsoft.VSCode": "development",
        "com.microsoft.VSCodeInsiders": "development",
        "com.visualstudio.code.oss": "development",
        "com.todesktop.230313mzl4w4u92": "development", // Cursor
        "dev.zed.Zed": "development",
        "com.googlecode.iterm2": "development",
        "com.apple.Terminal": "development",
        "dev.warp.Warp-Stable": "development",
        "com.github.GitHubClient": "development",
        "com.sublimetext.4": "development",
        "com.sublimetext.3": "development",
        "com.postmanlabs.mac": "development",
        "com.docker.docker": "development",
        "org.gnu.Emacs": "development",
        "com.apple.dt.Instruments": "development",

        // Communication
        "com.tinyspeck.slackmacgap": "communication",
        "com.apple.MobileSMS": "communication",
        "us.zoom.xos": "communication",
        "com.microsoft.teams2": "communication",
        "com.microsoft.teams": "communication",
        "com.apple.FaceTime": "communication",
        "com.apple.mail": "communication",
        "com.readdle.smartemail-Mac": "communication",
        "com.google.Gmail": "communication",

        // Social
        "com.hnc.Discord": "social",
        "net.whatsapp.WhatsApp": "social",
        "ph.telegra.Telegram": "social",
        "org.telegram.desktop": "social",
        "maccatalyst.com.atebits.Tweetie2": "social", // X / Twitter
        "com.facebook.archon": "social", // Messenger
        "com.reddit.reddit": "social",

        // Browsing
        "com.apple.Safari": "browsing",
        "com.google.Chrome": "browsing",
        "com.google.Chrome.canary": "browsing",
        "org.mozilla.firefox": "browsing",
        "company.thebrowser.Browser": "browsing", // Arc
        "com.brave.Browser": "browsing",
        "com.microsoft.edgemac": "browsing",
        "com.operasoftware.Opera": "browsing",
        "com.vivaldi.Vivaldi": "browsing",

        // Entertainment
        "com.spotify.client": "entertainment",
        "com.apple.Music": "entertainment",
        "com.apple.TV": "entertainment",
        "com.netflix.Netflix": "entertainment",
        "com.apple.podcasts": "entertainment",
        "com.colliderli.iina": "entertainment",
        "org.videolan.vlc": "entertainment",
        "tv.parsec.www": "entertainment",

        // Productivity
        "com.apple.iCal": "productivity",
        "com.apple.Notes": "productivity",
        "com.apple.reminders": "productivity",
        "md.obsidian": "productivity",
        "notion.id": "productivity",
        "com.culturedcode.ThingsMac": "productivity",
        "com.microsoft.Word": "productivity",
        "com.microsoft.Excel": "productivity",
        "com.microsoft.Powerpoint": "productivity",
        "com.microsoft.Outlook": "productivity",
        "com.apple.iWork.Pages": "productivity",
        "com.apple.iWork.Numbers": "productivity",
        "com.apple.iWork.Keynote": "productivity",
        "com.apple.Preview": "productivity",
        "com.linear": "productivity",
        "com.todoist.mac.Todoist": "productivity",

        // Design
        "com.figma.Desktop": "design",
        "com.bohemiancoding.sketch3": "design",

        // Utilities
        "com.apple.systempreferences": "utilities",
        "com.apple.SystemPreferences": "utilities",
        "com.apple.finder": "utilities",
        "com.apple.ActivityMonitor": "utilities",
        "com.apple.calculator": "utilities",
        "com.apple.ScreenSharing": "utilities",
    ]

    static let defaultPrefixRules: [(prefix: String, categoryID: String)] = [
        ("com.jetbrains.", "development"),
        ("com.google.android.studio", "development"),
        ("com.adobe.", "design"),
    ]
}
