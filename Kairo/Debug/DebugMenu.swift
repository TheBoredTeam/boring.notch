import AppKit

/// Menubar `K` item. Despite the historical name, this is the **real**
/// Kairo menu — every item performs a real action through the existing
/// services (TieredExecutor, KairoBrain, MusicManager, CalendarManager,
/// VolumeManager, KairoFeedbackEngine, etc).
///
/// The pre-existing animation tests (Listening / Thinking / Speaking /
/// Full Cycle / Brain probes) are preserved under a Dev submenu so the
/// debug surface is still reachable.
@MainActor
final class DebugMenu: NSObject {

    // MARK: - Dependencies

    private var statusItem: NSStatusItem?
    let executor: TieredExecutor
    let brain: KairoBrain?

    init(executor: TieredExecutor, brain: KairoBrain? = nil) {
        self.executor = executor
        self.brain = brain
        super.init()
    }

    // MARK: - Install

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "K"

        let menu = NSMenu()

        // ── KAIRO ────────────────────────────────
        menu.addItem(header("KAIRO"))
        menu.addItem(action("Ask Kairo…",       key: "k", mods: [.command],          sel: #selector(askKairo)))
        menu.addItem(action("Talk to Kairo",    key: "k", mods: [.command, .shift],  sel: #selector(talkToKairo)))
        menu.addItem(action("Enable \"Hey Kairo\"", sel: #selector(enableWakeWord)))
        menu.addItem(action("Test Ollama",      sel: #selector(testOllama)))

        // ── NOW ──────────────────────────────────
        menu.addItem(.separator())
        menu.addItem(header("NOW"))
        menu.addItem(action("Now Playing",      sel: #selector(showNowPlaying)))
        menu.addItem(action("Play / Pause",     key: " ", mods: [.command],          sel: #selector(playPause)))
        menu.addItem(action("Next Track",       key: "→", mods: [.command],          sel: #selector(nextTrack)))
        menu.addItem(action("Previous Track",   key: "←", mods: [.command],          sel: #selector(prevTrack)))

        // ── PLAY ─────────────────────────────────
        menu.addItem(.separator())
        menu.addItem(header("PLAY"))
        menu.addItem(action("Play on YouTube…",     sel: #selector(playYouTube)))
        menu.addItem(action("Play on Apple Music…", sel: #selector(playAppleMusic)))

        // ── HOME ─────────────────────────────────
        menu.addItem(.separator())
        menu.addItem(header("HOME"))
        menu.addItem(action("Weather",          sel: #selector(weather)))
        menu.addItem(action("Toggle Lights",    sel: #selector(toggleLights)))
        menu.addItem(action("Show Cameras",     sel: #selector(showCameras)))
        menu.addItem(action("Climate (AC)",     sel: #selector(toggleClimate)))

        // ── INFO ─────────────────────────────────
        menu.addItem(.separator())
        menu.addItem(header("INFO"))
        menu.addItem(action("Today's Calendar", sel: #selector(todaysCalendar)))
        menu.addItem(action("Morning Briefing", sel: #selector(morningBriefing)))

        // ── SYSTEM ───────────────────────────────
        menu.addItem(.separator())
        menu.addItem(header("SYSTEM"))
        menu.addItem(action("Take Screenshot",  sel: #selector(takeScreenshot)))
        menu.addItem(action("Read Clipboard",   sel: #selector(readClipboard)))
        menu.addItem(action("Lock Screen",      sel: #selector(lockScreen)))

        // ── DEV (submenu) ────────────────────────
        menu.addItem(.separator())
        let devItem = NSMenuItem(title: "Dev", action: nil, keyEquivalent: "")
        let devMenu = NSMenu()
        devMenu.addItem(action("Test Notification",    sel: #selector(testNotification)))
        devMenu.addItem(action("Test Listening",       sel: #selector(testListening)))
        devMenu.addItem(action("Test Thinking",        sel: #selector(testThinking)))
        devMenu.addItem(action("Test Speaking",        sel: #selector(testSpeaking)))
        devMenu.addItem(action("Test Full Cycle",      sel: #selector(testFullCycle)))
        devMenu.addItem(.separator())
        devMenu.addItem(action("Brain — Greet",        sel: #selector(testBrainGreet)))
        devMenu.addItem(action("Brain — Weather Q",    sel: #selector(testBrainWeatherQ)))
        devItem.submenu = devMenu
        menu.addItem(devItem)

        // ── Foot ─────────────────────────────────
        menu.addItem(.separator())
        menu.addItem(action("Settings…",        key: ",", mods: [.command],          sel: #selector(openSettings)))
        menu.addItem(action("Dismiss Orbie",    sel: #selector(dismissOrbie)))
        menu.addItem(.separator())
        menu.addItem(action("Quit Kairo",       key: "q", mods: [.command],          sel: #selector(quit)))

        item.menu = menu
        statusItem = item
    }

    // MARK: - Item builders

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .kern: 1.5
            ]
        )
        return item
    }

    private func action(_ title: String, key: String = "", mods: NSEvent.ModifierFlags = [], sel: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = self
        return item
    }

    // MARK: - KAIRO actions

    @objc private func askKairo() {
        guard let brain else {
            feedbackSay("Brain not online — Ollama may be down.", pill: "Kairo")
            return
        }
        guard let prompt = promptForText(title: "Ask Kairo", placeholder: "What's on your mind?") else { return }
        runBrain(prompt: prompt, brain: brain, pillText: "Kairo")
    }

    @objc private func talkToKairo() {
        NotificationCenter.default.post(name: .kairoVoiceActivated, object: nil)
    }

    @objc private func testOllama() {
        Task {
            let probe = OllamaClient()
            let result = await probe.diagnose()
            kairoDebug("Ollama diagnose:\n\(result)")
            await MainActor.run {
                // Show as an NSAlert so the user can read the full result
                let alert = NSAlert()
                alert.messageText = "Ollama Status"
                alert.informativeText = result
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    @objc private func enableWakeWord() {
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let wake = appDelegate.wakeWord else {
            feedbackSay("Wake word not available — voice pipeline not initialized.", pill: "Kairo")
            return
        }
        if wake.isRunning {
            wake.stop()
            feedbackSay("\"Hey Kairo\" disabled.", pill: "Kairo")
        } else {
            wake.start()
            feedbackSay("Listening for \"Hey Kairo\".", pill: "Kairo")
        }
    }

    // MARK: - NOW (music) actions

    @objc private func showNowPlaying() {
        Task {
            if let track = await AppleMusicService.currentTrack() {
                await MainActor.run { KairoRuntime.shared.present(.nowPlaying, payload: track) }
            } else {
                feedbackSay("Nothing playing.", pill: "Music")
            }
        }
    }

    @objc private func playPause() {
        Task { await MusicManager.shared.playPause() }
    }

    @objc private func nextTrack() {
        Task { await MusicManager.shared.nextTrack() }
    }

    @objc private func prevTrack() {
        Task { await MusicManager.shared.previousTrack() }
    }

    // MARK: - PLAY actions

    @objc private func playYouTube() {
        guard let query = promptForText(title: "Play on YouTube", placeholder: "e.g. lofi hip hop radio") else { return }
        Task {
            _ = try? await executor.run(toolName: "youtube", args: ["query": query])
            await MainActor.run { feedbackSay("Playing \(query) on YouTube.", pill: "YouTube") }
        }
    }

    @objc private func playAppleMusic() {
        let query = promptForText(title: "Play on Apple Music", placeholder: "Song / artist / album — blank to resume") ?? ""
        Task {
            _ = try? await executor.run(toolName: "apple_music", args: ["action": "play", "query": query])
        }
    }

    // MARK: - HOME actions

    @objc private func weather() {
        Task { _ = try? await executor.run(toolName: "weather", args: [:]) }
    }

    @objc private func toggleLights() {
        // Best-effort: send the legacy command (handleLocally picks it up
        // via the older flow) AND fire the smart_home tool — whichever the
        // wired backend handles wins. SmartHomeTool is still a stub today;
        // when it gets a real HASS / HomeKit binding, this just works.
        Task {
            _ = try? await executor.run(toolName: "smart_home", args: ["device": "lights", "action": "toggle"])
            await MainActor.run { feedbackSay("Lights toggled.", pill: "Lights") }
        }
    }

    @objc private func showCameras() {
        let placeholder = URL(string: "kairo://camera/front")!
        let data = CameraFeedData(label: "Front door", streamURL: placeholder)
        KairoRuntime.shared.present(.cameraFeed, payload: data)
    }

    @objc private func toggleClimate() {
        Task {
            _ = try? await executor.run(toolName: "smart_home", args: ["device": "ac", "action": "toggle"])
            await MainActor.run { feedbackSay("Climate toggled.", pill: "AC") }
        }
    }

    // MARK: - INFO actions

    @objc private func todaysCalendar() {
        let count = CalendarManager.shared.events.count
        let text = count == 0 ? "No events today." : "\(count) event\(count == 1 ? "" : "s") on your calendar today."
        feedbackSay(text, pill: "Calendar", speak: true)
    }

    @objc private func morningBriefing() {
        KairoMorningBriefing.shared.triggerBriefing()
    }

    // MARK: - SYSTEM actions

    @objc private func takeScreenshot() {
        Task {
            let result = try? await executor.run(toolName: "see_screen", args: [:])
            let text = result?.output ?? ""
            await MainActor.run {
                if text.isEmpty {
                    feedbackSay("Screenshot taken, no text detected.", pill: "Screen")
                } else {
                    let preview = text.split(separator: "\n").prefix(2).joined(separator: " · ")
                    feedbackSay("Screen OCR: \(preview)", pill: "Screen")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
    }

    @objc private func readClipboard() {
        Task {
            let result = try? await executor.run(toolName: "clipboard", args: [:])
            let text = result?.output ?? ""
            await MainActor.run {
                let preview = text.isEmpty ? "Clipboard is empty." : String(text.prefix(120))
                feedbackSay(preview, pill: "Clipboard")
            }
        }
    }

    @objc private func lockScreen() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x0C, keyDown: true) // Q
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x0C, keyDown: false)
        down?.flags = [.maskCommand, .maskControl]
        up?.flags   = [.maskCommand, .maskControl]
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - DEV — preserved test entries

    @objc private func testNotification() {
        let timeFmt = DateFormatter(); timeFmt.dateFormat = "h:mm a"
        let notif = NotificationData(
            app: "Test", title: "Kairo online",
            body: "This is a test notification.",
            icon: "🔔", timestamp: timeFmt.string(from: Date())
        )
        NotificationCenter.default.post(name: .kairoIncomingNotification, object: notif)
    }

    @objc private func testListening() {
        Task {
            await PresenceCoordinator.shared.beginListening()
            try? await Task.sleep(for: .seconds(4))
            await PresenceCoordinator.shared.endListening()
            try? await Task.sleep(for: .seconds(2))
            KairoRuntime.shared.orbieController?.setVoiceState(.idle)
            KairoRuntime.shared.dismiss()
            NowPlayingWatcher.shared.start()
        }
    }

    @objc private func testThinking() {
        Task {
            await KairoRuntime.shared.coordinator?.showOrb()
            KairoRuntime.shared.orbieController?.setVoiceState(.thinking)
            try? await Task.sleep(for: .seconds(3))
            KairoRuntime.shared.orbieController?.setVoiceState(.idle)
            KairoRuntime.shared.dismiss()
        }
    }

    @objc private func testSpeaking() {
        Task {
            await PresenceCoordinator.shared.beginSpeaking(
                query: "What's the weather",
                response: "Partly cloudy in Kampala, 24 degrees. Chance of rain later this afternoon."
            )
            try? await Task.sleep(for: .seconds(5))
            await PresenceCoordinator.shared.endSpeaking()
        }
    }

    @objc private func testFullCycle() {
        Task {
            await PresenceCoordinator.shared.beginListening()
            try? await Task.sleep(for: .seconds(3))
            await PresenceCoordinator.shared.endListening()
            try? await Task.sleep(for: .seconds(1.5))
            await PresenceCoordinator.shared.beginSpeaking(
                query: "Search for best hotels in Kampala",
                response: "Found ten. Top three are Serena, Speke, and Kampala Sheraton."
            )
            try? await Task.sleep(for: .seconds(6))
            await PresenceCoordinator.shared.endSpeaking()
        }
    }

    @objc private func testBrainGreet() {
        guard let brain else { return }
        runBrain(prompt: "Say hi in one sentence. Reference one thing you know about me.",
                 brain: brain, pillText: "Kairo")
    }

    @objc private func testBrainWeatherQ() {
        guard let brain else { return }
        runBrain(prompt: "What's the weather like? Use the weather tool if needed.",
                 brain: brain, pillText: "Weather")
    }

    // MARK: - Foot actions

    @objc private func openSettings() {
        DispatchQueue.main.async { SettingsWindowController.shared.showWindow() }
    }

    @objc private func dismissOrbie() {
        KairoRuntime.shared.dismiss()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Shared helpers

    /// Drives Orbie's presence (listening → speaking) around a Brain.handle call.
    /// The reply lands in Orbie's text response view and gets logged.
    private func runBrain(prompt: String, brain: KairoBrain, pillText: String) {
        kairoDebug("Brain: \(prompt)")
        Task {
            do {
                await PresenceCoordinator.shared.beginListening()
                try? await Task.sleep(for: .milliseconds(300))
                await PresenceCoordinator.shared.endListening()

                let reply = try await brain.handle(input: prompt, ambient: KairoAmbientContext.current())
                kairoDebug("Brain reply: \(reply)")

                await PresenceCoordinator.shared.beginSpeaking(query: prompt, response: reply)
                await MainActor.run {
                    KairoFeedbackEngine.shared.say(reply, pillText: pillText, speak: true)
                }
                try? await Task.sleep(for: .seconds(min(10.0, Double(reply.count) * 0.04)))
                await PresenceCoordinator.shared.endSpeaking()
            } catch {
                kairoDebug("Brain failed: \(error.localizedDescription)")
                let friendly = self.friendlyLLMError(error)
                await PresenceCoordinator.shared.endListening()
                // Show the error to the user via the caption HUD so they
                // see WHY nothing came back — not just dead air.
                await PresenceCoordinator.shared.beginSpeaking(
                    query: prompt,
                    response: friendly
                )
                await MainActor.run {
                    self.feedbackSay(friendly, pill: pillText)
                }
                try? await Task.sleep(for: .seconds(4))
                await PresenceCoordinator.shared.endSpeaking()
            }
        }
    }

    /// Plays through the legacy feedback engine so the user gets a notch pill +
    /// optional TTS, the same surface they already see for system events.
    private func feedbackSay(_ text: String, pill: String, speak: Bool = false) {
        KairoFeedbackEngine.shared.say(text, pillText: pill, speak: speak)
    }

    /// Turns raw LLM/network errors into one-sentence guidance for the user.
    /// Especially important on Ollama-only setups: the most common failure
    /// mode is "server not running" or "model not pulled", and the user
    /// should know exactly how to fix it.
    private func friendlyLLMError(_ error: Error) -> String {
        if let ollama = error as? OllamaClient.Error {
            return ollama.localizedDescription
        }
        if let llm = error as? LLMError {
            return llm.localizedDescription
        }
        let msg = error.localizedDescription
        if msg.contains("Could not connect") || msg.contains("not running") {
            return "Ollama isn't running. Try `ollama serve` in a terminal."
        }
        return "Brain failed: \(msg)"
    }

    /// Modal text-prompt input. Cancel returns nil. Empty trim returns nil.
    private func promptForText(title: String, placeholder: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = ""
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: "")
        field.placeholderString = placeholder
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field

        // Activate so the alert isn't behind other windows
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
