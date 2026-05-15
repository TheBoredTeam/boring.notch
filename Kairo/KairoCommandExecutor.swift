//
//  KairoCommandExecutor.swift
//  Kairo — Command execution with real-time voice feedback
//
//  Every action gets: BEFORE → DURING → AFTER voice feedback.
//  Never silent. Always confirms what it did.
//

import AppKit
import Foundation

// ═══════════════════════════════════════════
// MARK: - Intent Model
// ═══════════════════════════════════════════

struct KairoIntent {
    let intent: String
    let query: String?
    let app: String?
}

// ═══════════════════════════════════════════
// MARK: - Command Executor
// ═══════════════════════════════════════════

class KairoCommandExecutor {
    static let shared = KairoCommandExecutor()

    private let controller = KairoAppController.shared
    private let feedback = KairoFeedbackEngine.shared

    // ═══════════════════════════════════════
    // MARK: - Main Execute
    // ═══════════════════════════════════════

    func execute(_ intent: KairoIntent, original: String, retryCount: Int = 0) async {
        do {
            try await executeIntent(intent, original: original)
        } catch {
            // Retry up to 2 times on failure
            if retryCount < 2 {
                NSLog("Kairo: Command failed, retrying (%d/2)... %@", retryCount + 1, error.localizedDescription)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await execute(intent, original: original, retryCount: retryCount + 1)
            } else {
                feedback.say("I had trouble with that. Try saying it differently.", pillText: "⚠️ Failed")
                NSLog("Kairo: Command failed after 3 attempts: %@", error.localizedDescription)
            }
        }
    }

    private func executeIntent(_ intent: KairoIntent, original: String) async throws {
        switch intent.intent {

        // ─── Music ─────────────────────────
        case "play_youtube":
            await playYouTube(intent.query ?? original)

        case "play_spotify":
            playSpotify(intent.query ?? original)

        case "play_apple_music":
            playAppleMusic(intent.query ?? original)

        case "play_music":
            await playMusic(intent.query ?? original)

        case "pause_music":
            feedback.say("Paused", pillText: "⏸ Paused")
            sendMediaCommand(1)

        case "resume_music":
            feedback.say("Playing", pillText: "▶ Playing")
            sendMediaCommand(0)

        case "next_track":
            feedback.say("Next track", pillText: "⏭ Next")
            sendMediaCommand(4)

        case "prev_track":
            feedback.say("Going back", pillText: "⏮ Previous")
            sendMediaCommand(5)

        // ─── Volume ────────────────────────
        case "volume_up":
            adjustVolume(delta: 10)

        case "volume_down":
            adjustVolume(delta: -10)

        case "set_volume":
            if let q = intent.query,
               let level = Int(q.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
            {
                setVolume(level)
            }

        case "mute":
            toggleMute()

        // ─── Apps & URLs ───────────────────
        case "open_app":
            let app = intent.app ?? intent.query ?? original
            openApp(app)

        case "open_url":
            let url = intent.query ?? original
            feedback.say("Opening \(url)", pillText: "↗ \(url)")
            controller.openURL(url)

        case "google_search":
            let q = intent.query ?? original
            feedback.say("Searching for \(q)", pillText: "🔍 \(q)")
            controller.googleSearch(q)

        case "web_search":
            await KairoWebSearch.handleWebSearch(intent.query ?? original)

        // ─── Smart Home ────────────────────
        case "lights_on":
            await toggleLights(on: true)

        case "lights_off":
            await toggleLights(on: false)

        case "cinema_mode":
            await cinemaMode()

        case "ac_on":
            await toggleAC(on: true)

        case "ac_off":
            await toggleAC(on: false)

        case "good_night":
            await goodNight()

        case "away_mode":
            await awayMode()

        // ─── Info ──────────────────────────
        case "weather":
            await reportWeather()

        case "calendar":
            await reportCalendar()

        case "time":
            reportTime()

        // ─── System ────────────────────────
        case "screenshot":
            takeScreenshot()

        case "lock_screen":
            lockScreen()

        case "sleep_mac":
            feedback.say("Putting your Mac to sleep. Good night.", pillText: "💤 Sleeping...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
                controller.sleepMac()
            }

        // ─── General / Search ──────────────
        default:
            await handleGeneralQuery(original)
        }
    }

    // ═══════════════════════════════════════
    // MARK: - YouTube (Full Spoken Flow)
    // ═══════════════════════════════════════

    private func playYouTube(_ query: String) async {
        // STEP 1 — Announce
        feedback.say("Looking up \(query) on YouTube...", pillText: "🔍 YouTube: \(query)")

        try? await Task.sleep(nanoseconds: 600_000_000)

        // STEP 2 — Search YouTube API
        let apiKey = ProcessInfo.processInfo.environment["YOUTUBE_API_KEY"] ?? ""

        if !apiKey.isEmpty {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            if let url = URL(string: "https://www.googleapis.com/youtube/v3/search?part=snippet&q=\(encoded)&type=video&maxResults=1&videoCategoryId=10&key=\(apiKey)"),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]],
               let first = items.first
            {
                let videoID = (first["id"] as? [String: Any])?["videoId"] as? String ?? ""
                let snippet = first["snippet"] as? [String: Any] ?? [:]
                let videoTitle = (snippet["title"] as? String ?? query)
                    .replacingOccurrences(of: "&#39;", with: "'")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                let channelName = snippet["channelTitle"] as? String ?? ""

                if !videoID.isEmpty {
                    // STEP 3 — Confirm
                    let confirmation = channelName.isEmpty
                        ? "Playing \(videoTitle) on YouTube"
                        : "Playing \(videoTitle) by \(channelName) on YouTube"

                    await MainActor.run {
                        feedback.say(confirmation, pillText: "▶ \(videoTitle)")
                        let videoURL = "https://www.youtube.com/watch?v=\(videoID)"
                        controller.openInBrowserAndPlay(url: videoURL, videoID: videoID)
                    }
                    return
                }
            }
        }

        // Fallback
        await MainActor.run {
            feedback.say("Opening YouTube search for \(query)", pillText: "🔍 YouTube search...")
            controller.playOnYouTube(query)
        }
    }

    // ═══════════════════════════════════════
    // MARK: - Spotify
    // ═══════════════════════════════════════

    private func playSpotify(_ query: String) {
        feedback.say("Playing \(query) on Spotify", pillText: "🎵 Spotify: \(query)")

        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.spotify.client"
        }
        if !isRunning {
            feedback.flash("Opening Spotify...", duration: 2.0)
        }

        controller.playOnSpotify(query)
    }

    // ═══════════════════════════════════════
    // MARK: - Apple Music
    // ═══════════════════════════════════════

    private func playAppleMusic(_ query: String) {
        feedback.say("Playing \(query) on Apple Music", pillText: "🎵 Apple Music: \(query)")
        controller.playOnAppleMusic(query)
    }

    // ═══════════════════════════════════════
    // MARK: - Auto-detect Music Player
    // ═══════════════════════════════════════

    private func playMusic(_ query: String) async {
        let apps = NSWorkspace.shared.runningApplications.map { $0.bundleIdentifier ?? "" }

        if apps.contains("com.spotify.client") {
            playSpotify(query)
        } else if apps.contains("com.apple.Music") {
            playAppleMusic(query)
        } else {
            await playYouTube(query)
        }
    }

    // ═══════════════════════════════════════
    // MARK: - Volume
    // ═══════════════════════════════════════

    private func adjustVolume(delta: Int) {
        let direction = delta > 0 ? "up" : "down"
        let script = delta > 0
            ? "set volume output volume (output volume of (get volume settings) + \(abs(delta)))"
            : "set volume output volume (output volume of (get volume settings) - \(abs(delta)))"
        NSAppleScript(source: script)?.executeAndReturnError(nil)

        // Get new level
        let getLevel = NSAppleScript(source: "output volume of (get volume settings)")?.executeAndReturnError(nil)
        let newVol = Int(getLevel?.int32Value ?? 70)

        feedback.say("Volume \(newVol) percent", pillText: "🔊 \(newVol)%")
    }

    private func setVolume(_ level: Int) {
        let clamped = max(0, min(100, level))
        NSAppleScript(source: "set volume output volume \(clamped)")?.executeAndReturnError(nil)
        feedback.say("Volume set to \(clamped) percent", pillText: "🔊 \(clamped)%")
    }

    private func toggleMute() {
        NSAppleScript(source: "set volume with output muted")?.executeAndReturnError(nil)
        feedback.say("Muted", pillText: "🔇 Muted")
    }

    // ═══════════════════════════════════════
    // MARK: - Smart Home
    // ═══════════════════════════════════════

    private func toggleLights(on: Bool) async {
        feedback.say(
            on ? "Turning the lights on" : "Turning the lights off",
            pillText: on ? "💡 Lights on" : "💡 Lights off"
        )
        await callHomeAssistant(domain: "light", service: on ? "turn_on" : "turn_off", entity: "light.living_room")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            feedback.say(
                on ? "Lights are on" : "Lights are off",
                pillText: on ? "✅ Lights on" : "✅ Lights off"
            )
        }
    }

    private func toggleAC(on: Bool) async {
        feedback.say(
            on ? "Turning the AC on" : "Turning the AC off",
            pillText: on ? "❄️ AC on" : "❄️ AC off"
        )
        await callHomeAssistant(domain: "climate", service: on ? "turn_on" : "turn_off", entity: "climate.ac")
    }

    private func cinemaMode() async {
        feedback.say("Setting up cinema mode. Dimming lights and enabling Dolby.", pillText: "🎬 Cinema mode...")

        // Dim lights + set scene
        await callHomeAssistant(domain: "scene", service: "turn_on", entity: "scene.cinema")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [self] in
            feedback.say("Cinema mode ready. Enjoy the movie.", pillText: "🎬 Cinema ready")
        }
    }

    private func goodNight() async {
        feedback.say("Good night. Turning everything off.", pillText: "🌙 Good night...")

        await callHomeAssistant(domain: "scene", service: "turn_on", entity: "scene.good_night")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
            feedback.say("All done. Sleep well.", pillText: "🌙 Sleep well")
        }
    }

    private func awayMode() async {
        feedback.say("Away mode on. Securing the house.", pillText: "🏠 Away mode...")

        await callHomeAssistant(domain: "scene", service: "turn_on", entity: "scene.away")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [self] in
            feedback.say("House secured. Safe travels.", pillText: "✅ House secured")
        }
    }

    // ═══════════════════════════════════════
    // MARK: - Home Assistant API
    // ═══════════════════════════════════════

    private func callHomeAssistant(domain: String, service: String, entity: String) async {
        let haURL = ProcessInfo.processInfo.environment["HA_URL"] ?? ""
        let haToken = ProcessInfo.processInfo.environment["HA_TOKEN"] ?? ""
        guard !haURL.isEmpty, !haToken.isEmpty,
              let url = URL(string: "\(haURL)/api/services/\(domain)/\(service)")
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(haToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["entity_id": entity])

        _ = try? await URLSession.shared.data(for: request)
    }

    // ═══════════════════════════════════════
    // MARK: - Info Commands
    // ═══════════════════════════════════════

    private func reportWeather() async {
        feedback.flash("☁️ Checking weather...", duration: 2.0)

        await KairoWeatherService.shared.fetch()
        let w = KairoWeatherService.shared

        var response = "Outside it's \(Int(w.temp)) degrees and \(w.condition)"

        if w.willRain {
            response += ". Heads up — rain is expected today"
        }

        if let roomTemp = KairoHomeService.shared.roomTemp {
            response += ". Your room is \(Int(roomTemp)) degrees"
            if roomTemp > 27 {
                response += " — a bit warm, want me to turn on the AC?"
            }
        }

        feedback.say(response)
    }

    private func reportCalendar() async {
        feedback.flash("📅 Checking calendar...", duration: 2.0)

        let events = await fetchTodayEvents()

        if events.isEmpty {
            feedback.say("You have nothing scheduled today. A free day.", pillText: "📅 No events today")
        } else {
            var response = "You have \(events.count) \(events.count == 1 ? "event" : "events") today. "
            if let first = events.first {
                response += "First up: \(first)."
            }
            if events.count > 1, let second = events.dropFirst().first {
                response += " Then: \(second)."
            }
            feedback.say(response, pillText: "📅 \(events.count) events")
        }
    }

    private func reportTime() {
        let f = DateFormatter()
        f.timeStyle = .short
        let time = f.string(from: Date())
        feedback.say("It's \(time)", pillText: "🕐 \(time)")
    }

    private func fetchTodayEvents() async -> [String] {
        let store = EventKit.EKEventStore()
        return await withCheckedContinuation { cont in
            store.requestFullAccessToEvents { granted, _ in
                guard granted else { cont.resume(returning: []); return }
                let start = Calendar.current.startOfDay(for: Date())
                let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
                let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
                    .sorted { $0.startDate < $1.startDate }
                let f = DateFormatter(); f.timeStyle = .short
                let strings = events.map { "\($0.title ?? "Event") at \(f.string(from: $0.startDate))" }
                cont.resume(returning: strings)
            }
        }
    }

    // ═══════════════════════════════════════
    // MARK: - System Actions
    // ═══════════════════════════════════════

    private func openApp(_ name: String) {
        feedback.say("Opening \(name)", pillText: "↗ Opening \(name)...")
        controller.openApp(name)
    }

    private func takeScreenshot() {
        controller.takeScreenshot()
        feedback.say("Screenshot saved to your desktop", pillText: "📸 Screenshot saved")
    }

    private func lockScreen() {
        feedback.say("Locking your screen", pillText: "🔒 Locking...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            controller.lockScreen()
        }
    }

    // ═══════════════════════════════════════
    // MARK: - General Query Handler
    // ═══════════════════════════════════════

    func handleGeneralQuery(_ text: String) async {
        // Detect if it's a search question
        let searchKeywords = [
            "best", "find", "search", "look up",
            "what is", "who is", "where is",
            "how do", "what are", "tell me about",
            "restaurants", "hotels", "places",
            "news", "weather in", "price of",
        ]

        let lower = text.lowercased()
        let isSearchQuery = searchKeywords.contains { lower.contains($0) }

        if isSearchQuery {
            await KairoWebSearch.handleWebSearch(text)
            return
        }

        // Direct AI response
        feedback.say("Let me think...", pillText: "💭 Thinking...")

        let response = await KairoWebSearch.askClaude(text)
        feedback.say(response)
    }

    // ═══════════════════════════════════════
    // MARK: - Media Remote Helper
    // ═══════════════════════════════════════

    private func sendMediaCommand(_ command: Int) {
        // Use AppleScript as fallback since MRMediaRemote requires private framework
        let commandMap: [Int: String] = [
            0: "play", 1: "pause", 4: "next track", 5: "previous track",
        ]
        if let action = commandMap[command] {
            let script = """
                tell application "System Events"
                    key code \(command == 0 || command == 1 ? 49 : (command == 4 ? 124 : 123)) using {command down}
                end tell
                """
            // Use NowPlaying approach instead
            let mediaScript = """
                tell application "Music"
                    \(action)
                end tell
                """
            NSAppleScript(source: mediaScript)?.executeAndReturnError(nil)
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - EventKit Import
// ═══════════════════════════════════════════

import EventKit
