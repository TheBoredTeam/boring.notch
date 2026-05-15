import AppKit

@MainActor
final class DebugMenu: NSObject {
    private var statusItem: NSStatusItem?
    let executor: TieredExecutor
    let brain: KairoBrain?

    init(executor: TieredExecutor, brain: KairoBrain? = nil) {
        self.executor = executor
        self.brain = brain
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "K"

        let menu = NSMenu()
        menu.addItem(itemFor("Test Weather",      selector: #selector(testWeather)))
        menu.addItem(itemFor("Test Music",        selector: #selector(testMusic)))
        menu.addItem(itemFor("Test YouTube",      selector: #selector(testYouTube)))
        menu.addItem(itemFor("Test Notification", selector: #selector(testNotification)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(itemFor("Test Listening",    selector: #selector(testListening)))
        menu.addItem(itemFor("Test Thinking",     selector: #selector(testThinking)))
        menu.addItem(itemFor("Test Speaking",     selector: #selector(testSpeaking)))
        menu.addItem(itemFor("Test Full Cycle",   selector: #selector(testFullCycle)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(itemFor("Test Brain — Greet",      selector: #selector(testBrainGreet)))
        menu.addItem(itemFor("Test Brain — Weather Q",  selector: #selector(testBrainWeatherQ)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(itemFor("Dismiss Orbie",     selector: #selector(dismiss)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(itemFor("Quit",              selector: #selector(quit)))

        item.menu = menu
        statusItem = item
    }

    private func itemFor(_ title: String, selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func testWeather() {
        kairoDebug("testWeather tapped")
        Task { _ = try? await executor.run(toolName: "weather", args: [:]) }
    }

    @objc private func testMusic() {
        Task { _ = try? await executor.run(toolName: "apple_music", args: ["action": "play"]) }
    }

    @objc private func testYouTube() {
        Task { _ = try? await executor.run(toolName: "youtube", args: ["query": "lofi hip hop"]) }
    }

    @objc private func testNotification() {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"
        let notif = NotificationData(
            app: "Test",
            title: "Kairo online",
            body: "This is a test notification.",
            icon: "🔔",
            timestamp: timeFmt.string(from: Date())
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
            kairoDebug("testThinking: start")
            await KairoRuntime.shared.coordinator?.showOrb()
            KairoRuntime.shared.orbieController?.setVoiceState(.thinking)
            kairoDebug("testThinking: thinking state set")
            try? await Task.sleep(for: .seconds(3))
            KairoRuntime.shared.orbieController?.setVoiceState(.idle)
            KairoRuntime.shared.dismiss()
            kairoDebug("testThinking: done")
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
        kairoDebug("testFullCycle: triggered")
        Task {
            kairoDebug("testFullCycle: Task started")
            await PresenceCoordinator.shared.beginListening()
            kairoDebug("testFullCycle: listening started, sleeping 3s")
            try? await Task.sleep(for: .seconds(3))
            kairoDebug("testFullCycle: calling endListening")
            await PresenceCoordinator.shared.endListening()
            kairoDebug("testFullCycle: listening ended, sleeping 1.5s")
            try? await Task.sleep(for: .seconds(1.5))
            kairoDebug("testFullCycle: calling beginSpeaking")
            await PresenceCoordinator.shared.beginSpeaking(
                query: "Search for best hotels in Kampala",
                response: "Found ten. Top three are Serena, Speke, and Kampala Sheraton. Want details on any?"
            )
            kairoDebug("testFullCycle: speaking started, sleeping 6s")
            try? await Task.sleep(for: .seconds(6))
            kairoDebug("testFullCycle: calling endSpeaking")
            await PresenceCoordinator.shared.endSpeaking()
            kairoDebug("testFullCycle: complete")
        }
    }

    // MARK: - Brain tests

    @objc private func testBrainGreet() {
        runBrain(prompt: "Say hi in one sentence. Reference one thing you know about me.")
    }

    @objc private func testBrainWeatherQ() {
        runBrain(prompt: "What's the weather like? Use the weather tool if needed.")
    }

    private func runBrain(prompt: String) {
        guard let brain else {
            kairoDebug("Brain not wired — skipping prompt: \(prompt)")
            return
        }
        kairoDebug("Brain test: \(prompt)")
        Task {
            do {
                await PresenceCoordinator.shared.beginListening()
                try? await Task.sleep(for: .milliseconds(400))
                await PresenceCoordinator.shared.endListening()

                let reply = try await brain.handle(input: prompt, ambient: KairoAmbientContext.current())
                kairoDebug("Brain reply: \(reply)")

                await PresenceCoordinator.shared.beginSpeaking(query: prompt, response: reply)
                try? await Task.sleep(for: .seconds(min(8.0, Double(reply.count) * 0.04)))
                await PresenceCoordinator.shared.endSpeaking()
            } catch {
                kairoDebug("Brain failed: \(error.localizedDescription)")
                await PresenceCoordinator.shared.endListening()
            }
        }
    }

    @objc private func dismiss() {
        KairoRuntime.shared.dismiss()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
