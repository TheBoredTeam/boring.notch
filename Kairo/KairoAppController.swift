//
//  KairoAppController.swift
//  Kairo — Browser and app control
//
//  Opens apps, URLs, YouTube videos, Spotify, Apple Music.
//  Actually PLAYS content — not just opens it.
//  Uses AppleScript + JS injection for true autoplay.
//

import AppKit
import SwiftUI

// ═══════════════════════════════════════════
// MARK: - Browser Detection
// ═══════════════════════════════════════════

enum KairoBrowser {
    case chrome, safari, firefox
    case other(String)
}

class KairoAppController {
    static let shared = KairoAppController()

    // ═══════════════════════════════════════
    // MARK: - Browser Detection
    // ═══════════════════════════════════════

    func getDefaultBrowser() -> KairoBrowser {
        guard let url = URL(string: "https://"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url)
        else { return .safari }

        let bundleID = Bundle(url: appURL)?.bundleIdentifier?.lowercased() ?? ""

        if bundleID.contains("chrome") { return .chrome }
        if bundleID.contains("safari") { return .safari }
        if bundleID.contains("firefox") { return .firefox }
        return .other(appURL.lastPathComponent.replacingOccurrences(of: ".app", with: ""))
    }

    // ═══════════════════════════════════════
    // MARK: - YouTube (AppleScript autoplay)
    // ═══════════════════════════════════════

    func playOnYouTube(_ query: String) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = "https://www.youtube.com/results?search_query=\(encoded)"
        openInBrowserAndPlay(url: url)
        NSLog("Kairo: YouTube search → %@", query)
    }

    func playYouTubeDirectly(_ query: String) async {
        let apiKey = ProcessInfo.processInfo.environment["YOUTUBE_API_KEY"] ?? ""
        guard !apiKey.isEmpty else { await MainActor.run { playOnYouTube(query) }; return }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let apiURL = URL(string: "https://www.googleapis.com/youtube/v3/search?part=snippet&q=\(encoded)&type=video&maxResults=1&videoCategoryId=10&key=\(apiKey)") else {
            await MainActor.run { playOnYouTube(query) }; return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: apiURL)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]], let first = items.first,
               let id = first["id"] as? [String: Any], let videoID = id["videoId"] as? String {
                let snippet = first["snippet"] as? [String: Any]
                let title = (snippet?["title"] as? String ?? query)
                    .replacingOccurrences(of: "&#39;", with: "'")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                let videoURL = "https://www.youtube.com/watch?v=\(videoID)"
                await MainActor.run {
                    openInBrowserAndPlay(url: videoURL, videoID: videoID)
                }
                NSLog("Kairo: YouTube playing → %@", title)
                return
            }
        } catch {}
        await MainActor.run { playOnYouTube(query) }
    }

    // ═══════════════════════════════════════
    // MARK: - Browser Control (Full Autoplay)
    // ═══════════════════════════════════════

    func openInBrowserAndPlay(url: String, videoID: String = "") {
        let browser = getDefaultBrowser()

        switch browser {
        case .chrome:
            openInChromeAndPlay(url: url, videoID: videoID)
        case .safari:
            openInSafariAndPlay(url: url, videoID: videoID)
        case .firefox:
            openInFirefoxAndPlay(url: url, videoID: videoID)
        case .other:
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }

        NSLog("Kairo: Browser play → %@", url)
    }

    // MARK: Chrome — AppleScript + JS Injection

    private func openInChromeAndPlay(url: String, videoID: String) {
        let openScript = """
        tell application "Google Chrome"
            activate
            if (count of windows) = 0 then make new window
            tell front window
                set newTab to make new tab with properties {URL:"\(url)"}
                set active tab index to index of newTab
            end tell
        end tell
        """
        NSAppleScript(source: openScript)?.executeAndReturnError(nil)

        // Inject JS at multiple intervals to handle page load + ads
        for delay in [3.5, 5.5, 8.0, 10.0, 12.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.injectChromeAutoplayJS()
            }
        }
    }

    private func injectChromeAutoplayJS() {
        let js = """
            var skip = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, [class*="skip-button"]');
            if (skip) { skip.click(); }
            var video = document.querySelector('video');
            if (video) { video.play(); video.muted = false; }
            var playBtn = document.querySelector('.ytp-play-button[aria-label*="Play"]');
            if (playBtn) { playBtn.click(); }
            var overlay = document.querySelector('.ytp-cued-thumbnail-overlay');
            if (overlay) { overlay.click(); }
        """.replacingOccurrences(of: "\n", with: " ")

        let inject = """
        tell application "Google Chrome"
            tell front window
                tell active tab
                    execute javascript "\(js)"
                end tell
            end tell
        end tell
        """
        NSAppleScript(source: inject)?.executeAndReturnError(nil)
    }

    // MARK: Safari — AppleScript + JS Injection

    private func openInSafariAndPlay(url: String, videoID: String) {
        let script = """
        tell application "Safari"
            activate
            if (count of windows) = 0 then make new document
            tell front window to set current tab to (make new tab with properties {URL:"\(url)"})
        end tell
        """
        NSAppleScript(source: script)?.executeAndReturnError(nil)

        // Safari needs longer load time
        for delay in [4.5, 7.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let jsScript = """
                tell application "Safari"
                    tell front document
                        do JavaScript "var v=document.querySelector('video');if(v){v.play();v.muted=false;} var s=document.querySelector('.ytp-skip-ad-button,.ytp-ad-skip-button');if(s){s.click();} var o=document.querySelector('.ytp-cued-thumbnail-overlay');if(o){o.click();}"
                    end tell
                end tell
                """
                NSAppleScript(source: jsScript)?.executeAndReturnError(nil)
            }
        }
    }

    // MARK: Firefox — Embed URL with autoplay=1

    private func openInFirefoxAndPlay(url: String, videoID: String) {
        // Firefox doesn't support AppleScript JS injection well
        // Use embed URL with autoplay param instead
        let playURL: String
        if !videoID.isEmpty {
            playURL = "https://www.youtube.com/embed/\(videoID)?autoplay=1&mute=0"
        } else {
            playURL = url
        }

        if let u = URL(string: playURL) {
            let config = NSWorkspace.OpenConfiguration()
            if let firefoxURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.mozilla.firefox") {
                NSWorkspace.shared.open([u], withApplicationAt: firefoxURL, configuration: config) { _, _ in }
            } else {
                NSWorkspace.shared.open(u)
            }
        }
    }

    // ═══════════════════════════════════════
    // MARK: - Spotify (Actually Plays)
    // ═══════════════════════════════════════

    func playOnSpotify(_ query: String) {
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.spotify.client"
        }

        if !isRunning {
            // Launch Spotify first, then search + play after it's ready
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.spotifySearchAndPlay(query)
            }
        } else {
            spotifySearchAndPlay(query)
        }
    }

    private func spotifySearchAndPlay(_ query: String) {
        let safe = query
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\\", with: "")

        // Open Spotify search URI, wait, then hit play
        let script = """
        tell application "Spotify"
            activate
            open location "spotify:search:\(safe)"
            delay 2
            play
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)

        if err != nil {
            // Fallback — at least open the search
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            if let uri = URL(string: "spotify:search:\(encoded)") {
                NSWorkspace.shared.open(uri)
            }
            NSLog("Kairo: Spotify AppleScript failed, fell back to URI")
        } else {
            NSLog("Kairo: Spotify playing → %@", query)
        }
    }

    // ═══════════════════════════════════════
    // MARK: - Apple Music (Actually Plays)
    // ═══════════════════════════════════════

    func playOnAppleMusic(_ query: String) {
        let escaped = query
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\\", with: "")

        // Search library first, if not found open Apple Music search
        let script = """
        tell application "Music"
            activate
            set searchResults to (search playlist "Library" for "\(escaped)")
            if (count of searchResults) > 0 then
                play item 1 of searchResults
            else
                open location "music://music.apple.com/search?term=\(escaped.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? escaped)"
                delay 2
                play
            end if
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)

        if error != nil {
            // Fallback: open Music app search URL
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            if let url = URL(string: "music://music.apple.com/search?term=\(encoded)") {
                NSWorkspace.shared.open(url)
            }
            NSLog("Kairo: Apple Music AppleScript failed, fell back to URL")
        } else {
            NSLog("Kairo: Apple Music playing → %@", query)
        }
    }

    // ═══════════════════════════════════════
    // MARK: - Automation Permission Check
    // ═══════════════════════════════════════

    func checkAndRequestAutomation() {
        let testScript = """
        tell application "System Events"
            return name of first process
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: testScript)?.executeAndReturnError(&err)

        if err != nil {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Allow Kairo to control your apps"
                alert.informativeText = """
                To play music and videos automatically, Kairo needs Automation permission for:

                • Google Chrome (YouTube autoplay)
                • Spotify (music playback)
                • Apple Music (music playback)
                • System Events (system controls)

                Click Open Settings and enable each app under Kairo in Automation.
                """
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Later")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } else {
            NSLog("Kairo: ✅ Automation permissions OK")
        }
    }

    // MARK: - Open Any App

    func openApp(_ appName: String) {
        let bundleIDs: [String: String] = [
            "chrome": "com.google.Chrome", "safari": "com.apple.Safari", "firefox": "org.mozilla.firefox",
            "spotify": "com.spotify.client", "music": "com.apple.Music", "mail": "com.apple.mail",
            "calendar": "com.apple.iCal", "messages": "com.apple.MobileSMS", "slack": "com.tinyspeck.slackmacgap",
            "telegram": "ru.keepcoder.Telegram", "whatsapp": "net.whatsapp.WhatsApp", "zoom": "us.zoom.xos",
            "vscode": "com.microsoft.VSCode", "xcode": "com.apple.dt.Xcode", "terminal": "com.apple.Terminal",
            "finder": "com.apple.finder", "photos": "com.apple.Photos", "notes": "com.apple.Notes",
            "discord": "com.hnc.Discord",
        ]

        let key = appName.lowercased().replacingOccurrences(of: " ", with: "")
        if let bid = bundleIDs[key], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            NSLog("Kairo: Opened %@ via bundle ID", appName)
            return
        }
        // Fallback: launch by name via open command
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", appName]
        try? task.run()
        NSLog("Kairo: Opened %@ by name", appName)
    }

    // MARK: - URLs & Search

    func openURL(_ urlString: String) {
        var final = urlString
        if !final.hasPrefix("http") { final = "https://" + final }
        if let url = URL(string: final) { NSWorkspace.shared.open(url) }
    }

    func googleSearch(_ query: String) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if let url = URL(string: "https://www.google.com/search?q=\(encoded)") { NSWorkspace.shared.open(url) }
    }

    // MARK: - System Actions

    func takeScreenshot() {
        let path = "\(NSHomeDirectory())/Desktop/kairo-screenshot-\(Int(Date().timeIntervalSince1970)).png"
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); task.arguments = ["-i", path]
        try? task.run()
    }

    func lockScreen() {
        NSAppleScript(source: "tell application \"System Events\" to keystroke \"q\" using {control down, command down}")?.executeAndReturnError(nil)
    }

    func sleepMac() {
        NSAppleScript(source: "tell application \"System Events\" to sleep")?.executeAndReturnError(nil)
    }

    func setSystemVolume(_ percent: Int) {
        NSAppleScript(source: "set volume output volume \(max(0, min(100, percent)))")?.executeAndReturnError(nil)
    }

    // MARK: - Route Intent from Claude
    //
    // All intents now go through KairoCommandExecutor
    // which provides voice feedback on every action.

    func routeIntent(intent: String, query: String?) async {
        let kairoIntent = KairoIntent(intent: intent, query: query, app: query)
        await KairoCommandExecutor.shared.execute(kairoIntent, original: query ?? "")
    }

    private func autoDetectAndPlay(_ query: String) async {
        let running = NSWorkspace.shared.runningApplications
        if running.contains(where: { $0.bundleIdentifier == "com.spotify.client" }) {
            await MainActor.run { playOnSpotify(query) }
        } else if running.contains(where: { $0.bundleIdentifier == "com.apple.Music" }) {
            await MainActor.run { playOnAppleMusic(query) }
        } else {
            await playYouTubeDirectly(query)
        }
    }
}
