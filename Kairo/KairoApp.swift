//
//  KairoApp.swift
//  Kairo
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        // Initialize the settings window controller with the updater controller
        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        MenuBarExtra("Kairo", systemImage: "brain.head.profile", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            CheckForUpdatesView(updater: updaterController.updater)
            Divider()
            Button("Restart Kairo") {
                ApplicationRelauncher.restart()
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:] // UUID -> NSWindow
    var viewModels: [String: KairoViewModel] = [:] // UUID -> KairoViewModel
    var window: NSWindow?
    // Voice button window removed — voice lives inside the notch
    let vm: KairoViewModel = .init()
    @ObservedObject var coordinator = KairoViewCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?

    // v3 Orbie + Note handoff
    var orbieWindow: OrbieWindow?
    var orbieController: OrbieController?
    var orbCoordinator: OrbCoordinator?
    var noteWindow: NoteWindow?
    var debugMenu: DebugMenu?
    var tieredExecutor: TieredExecutor?

    // Brain pipeline — instantiated in applicationDidFinishLaunching.
    var brain: KairoBrain?
    var shortTermMemory: KairoShortTermMemory?
    var longTermMemory: KairoLongTermMemory?
    var conversationHistory: KairoConversationHistory?

    // Voice pipeline — recognizer, TTS, wake word, conversation loop.
    // All driven by KairoWakeWord ("hey kairo") and F5 (KairoVoiceTrigger).
    var speechRecognizer: KairoSpeechRecognizer?
    var ttsEngine: KairoTTSEngine?
    var wakeWord: KairoWakeWord?
    var conversationLoop: KairoConversationLoop?
    private var orbieCancellables = Set<AnyCancellable>()
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // Load API keys from ~/.kairo.env or ~/AI/Kairo/.env
    func loadEnvFile() {
        let paths = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kairo.env").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AI/Kairo/.env").path,
        ]
        for path in paths {
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            contents.components(separatedBy: .newlines)
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                .forEach { line in
                    let parts = line.components(separatedBy: "=")
                    guard parts.count >= 2 else { return }
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { setenv(key, value, 0) } // 0 = don't overwrite existing
                }
            print("[Kairo] ENV loaded from \(path)")
            return
        }
        print("[Kairo] No .env file found")
    }

    @objc func runVerification() {
        Task { await KairoVerification.runAll() }
    }

    func connectBackendWithRetry() async {
        let serverURL = "ws://localhost:8420/ws"
        for attempt in 1...5 {
            print("[Kairo] Backend connection attempt \(attempt)/5...")
            KairoSocket.shared.connect()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if KairoSocket.shared.isConnected {
                print("[Kairo] Backend connected")
                return
            }
        }
        print("[Kairo] Running in local mode (no backend)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        MusicManager.shared.destroy()
        cleanupDragDetectors()
        cleanupWindows()
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        if !Defaults[.showOnLockScreen] {
            adjustWindowPosition(changeAlpha: true)
        } else {
            disableSkyLightOnAllWindows()
        }

        // Jarvis welcome — greet user on unlock
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.triggerJarvisWelcome()
        }
    }

    private func triggerJarvisWelcome() {
        guard KairoSocket.shared.isConnected else { return }

        KairoMorningBriefing.shared.hasGreetedToday = true

        Task {
            do {
                // Call the backend /welcome endpoint
                guard let url = URL(string: "http://localhost:8420/welcome") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 20

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { return }

                // Get the briefing text from header
                let briefingText = httpResponse.value(forHTTPHeaderField: "X-Kairo-Response") ?? "Welcome back."

                // Show in notch
                await MainActor.run {
                    self.vm.open()
                    KairoFeedbackEngine.shared.say(briefingText, pillText: "Welcome back")
                }

                // Play the TTS audio
                KairoFeedbackEngine.shared.playAudioData(data)

                // Auto-close notch after briefing
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                await MainActor.run { self.vm.close() }

            } catch {
                print("[Kairo] Welcome briefing failed: \(error)")
            }
        }
    }
    
    @MainActor
    private func enableSkyLightOnAllWindows() {
        if Defaults[.showOnAllDisplays] {
            windows.values.forEach { window in
                if let skyWindow = window as? KairoSkyLightWindow {
                    skyWindow.enableSkyLight()
                }
            }
        } else {
            if let skyWindow = window as? KairoSkyLightWindow {
                skyWindow.enableSkyLight()
            }
        }
    }
    
    @MainActor
    private func disableSkyLightOnAllWindows() {
        // Delay disabling SkyLight to avoid flicker during unlock transition
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    self.windows.values.forEach { window in
                        if let skyWindow = window as? KairoSkyLightWindow {
                            skyWindow.disableSkyLight()
                        }
                    }
                } else {
                    if let skyWindow = self.window as? KairoSkyLightWindow {
                        skyWindow.disableSkyLight()
                    }
                }
            }
        }
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]
        
        if shouldCleanupMulti {
            windows.values.forEach { window in
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            self.window = nil
        }
    }

    private func cleanupDragDetectors() {
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = window?.screen
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        let screenFrame = screen.frame
        let notchHeight = openNotchSize.height
        let notchWidth = openNotchSize.width
        
        // Create notch region at the top-center of the screen where an open notch would occupy
        let notchRegion = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        
        let detector = DragDetector(notchRegion: notchRegion)
        
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }
        
        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            viewModel.open()
            coordinator.currentView = .shelf
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen, screen == windowScreen {
            vm.open()
            coordinator.currentView = .shelf
        }
    }

    private func createKairoWindow(for screen: NSScreen, with viewModel: KairoViewModel) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        
        let window = KairoSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        
        // Enable SkyLight only when screen is locked
        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        window.contentView = NSHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        // Observe when the window's screen changes so we can update drag detectors
        windowScreenDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDragDetectors()
                }
        }
        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
        window.alphaValue = 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        // Load API keys from env files
        loadEnvFile()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            Task { @MainActor in
                window.alphaValue = self.coordinator.selectedScreenUUID == self.coordinator.preferredScreenUUID ? 1 : 0
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        }

        // Use closure-based observers for DistributedNotificationCenter and keep tokens for removal
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenUnlocked(notification)
                }
        }

        // Cmd+Shift+K pressed → open notch + start voice mode
        KeyboardShortcuts.onKeyDown(for: .kairoCommand) { [weak self] in
            guard let self = self else { return }
            self.vm.open()
            // Activate voice listening in the notch
            NotificationCenter.default.post(name: .kairoVoiceActivated, object: nil)
        }

        // Cmd+Shift+K released → stop listening, process voice
        KeyboardShortcuts.onKeyUp(for: .kairoCommand) { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .kairoVoiceDismissed, object: nil)
            // Auto-close notch after response
            self.closeNotchTask?.cancel()
            self.closeNotchTask = Task {
                do {
                    try await Task.sleep(for: .seconds(10))
                    await MainActor.run { self.vm.close() }
                } catch {}
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            if Defaults[.sneakPeekStyles] == .inline {
                let newStatus = !self.coordinator.expandingView.show
                self.coordinator.toggleExpandingView(status: newStatus, type: .music)
            } else {
                self.coordinator.toggleSneakPeek(
                    status: !self.coordinator.sneakPeek.show,
                    type: .music,
                    duration: 3.0
                )
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }

                let mouseLocation = NSEvent.mouseLocation

                var viewModel = self.vm

                if Defaults[.showOnAllDisplays] {
                    for screen in NSScreen.screens {
                        if screen.frame.contains(mouseLocation) {
                            if let uuid = screen.displayUUID, let screenViewModel = self.viewModels[uuid] {
                                viewModel = screenViewModel
                                break
                            }
                        }
                    }
                }

                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    await MainActor.run {
                        viewModel.open()
                    }

                    let task = Task { [weak viewModel] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.close()
                            }
                        } catch { }
                    }
                    self.closeNotchTask = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createKairoWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        setupDragDetectors()

        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        } else if MusicManager.shared.isNowPlayingDeprecated
            && Defaults[.mediaController] == .nowPlaying
        {
            DispatchQueue.main.async {
                self.showOnboardingWindow(step: .musicPermission)
            }
        }

        previousScreens = NSScreen.screens

        // 1. Hologram orb — keep existing init, just grab reference
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            KairoHologramWindow.shared.show()
        }

        // 2. Orbie — hidden initially, coordinator owns visibility
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let controller = OrbieController()
            self.orbieController = controller

            let shell = OrbieShell().environmentObject(controller)
            let orbWin = OrbieWindow()
            orbWin.contentView = NSHostingView(rootView: shell)
            orbWin.alphaValue = 0
            orbWin.orderOut(nil)
            self.orbieWindow = orbWin

            // Resize when mode changes
            controller.$mode
                .map { _ in controller.currentSize }
                .removeDuplicates()
                .sink { [weak orbWin] size in orbWin?.resize(to: size) }
                .store(in: &self.orbieCancellables)

            // 3. Coordinator owns the handoff
            let coord = OrbCoordinator(
                hologram: KairoHologramWindow.shared,
                orbieWindow: orbWin,
                orbieController: controller
            )
            self.orbCoordinator = coord
            KairoRuntime.shared.coordinator = coord

            // 2b. Register tools and install debug menu
            let gate = PermissionGate()
            let executor = TieredExecutor(permissionGate: gate)
            executor.register(WeatherTool())
            executor.register(AppleMusicTool())
            executor.register(YouTubeTool())
            executor.register(ScreenTool())
            executor.register(ClipboardTool())
            executor.register(SystemTool())
            executor.register(SmartHomeTool())
            executor.register(SearchTool())
            executor.register(WebReadTool())
            executor.register(CalendarEventTool())
            executor.register(VisionTool())
            executor.register(PerceiveTool())
            self.tieredExecutor = executor

            // 2c. Brain pipeline — provider-agnostic LLM client + memory.
            //     LLM order: Ollama (local) → Anthropic → OpenAI. Any of
            //     the three that's configured will be tried; failures
            //     fall through silently to the next. So Kairo works
            //     offline-first but stays alive when Ollama is down,
            //     provided a cloud key is set in ~/.kairo.env.
            let shortTerm = KairoShortTermMemory()
            let longTerm  = KairoLongTermMemory()
            let history   = KairoConversationHistory()
            let contextBuilder = ContextBuilder()
            // Only include cloud backends if their keys are actually in env.
            // Most users (you included) are Ollama-only — this keeps the
            // fallback errors clean and the chain log honest.
            let llm: LLMClient = LLMFallbackClient.configuredChain()
            let brain = KairoBrain(
                llm: llm,
                contextBuilder: contextBuilder,
                executor: executor,
                shortTerm: shortTerm,
                longTerm: longTerm,
                history: history
            )
            self.shortTermMemory = shortTerm
            self.longTermMemory  = longTerm
            self.conversationHistory = history
            self.brain = brain
            print("[Kairo] LLM chain: \(llm.label)")
            print("[Kairo] Conversation history: \(history.turns.count) past turns loaded")
            // Surface agent state in the CaptionHUD so the user sees
            // Thinking / Searching / Reading / Acting / Speaking as the
            // ReAct loop iterates.
            brain.stateObserver = { state in
                Task { @MainActor in KairoCaptionHUD.shared.updateAgentState(state) }
            }
            print("[Kairo] Brain pipeline online — \(longTerm.all().count) facts in long-term memory")

            // 2d. Voice pipeline — TTS, speech recognizer, wake word, conversation loop.
            //     ConversationLoop binds onWake → startTurn. WakeWord
            //     starts listening for "hey kairo" continuously.
            let tts = KairoTTSEngine()
            let recognizer = KairoSpeechRecognizer()
            let wake = KairoWakeWord()
            let loop = KairoConversationLoop(
                wake: wake, recognizer: recognizer, brain: brain, tts: tts
            )
            self.ttsEngine = tts
            self.speechRecognizer = recognizer
            self.wakeWord = wake
            self.conversationLoop = loop
            // Wake word NOT started automatically. Continuous audio access at
            // app launch can trigger a TCC kill in sandboxed macOS apps. Users
            // can enable it from K menubar → "Enable Hey Kairo". F5 still
            // works (routes to ConversationLoop), and ConversationLoop's own
            // permission request happens at the user's explicit invocation.
            print("[Kairo] Voice pipeline online — wake word disabled (enable in menu)")

            let debug = DebugMenu(executor: executor, brain: brain)
            debug.install()
            self.debugMenu = debug

            // Demo: real weather fetch after 5s
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                Task { _ = try? await executor.run(toolName: "weather", args: [:]) }
            }
        }

        // 4. Note — persistent side panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            let noteWin = NoteWindow()
            noteWin.contentView = NSHostingView(rootView: NoteShell())
            noteWin.orderFrontRegardless()
            self.noteWindow = noteWin
        }

        // 5. Now-playing watcher + notification monitor + WebSocket server
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            NowPlayingWatcher.shared.start()
            NotificationMonitor.shared.start()
            KairoWebSocketServer.shared.start()
        }

        // === KAIRO SYSTEMS ===
        // Step 1: Start LOCAL systems immediately (no backend needed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            KairoMusicBridge.shared.startBridging()
            KairoVoiceTrigger.shared.start()
            KairoSystemEventBridge.shared.start()
            KairoNotificationEngine.shared.requestPermissions()
            KairoHomeService.shared.startAutoRefresh()
            Task { await KairoWeatherService.shared.fetch(); await KairoHomeService.shared.fetchStatus() }
        }

        // Step 2: Connect to backend with retry (non-blocking)
        Task {
            await self.connectBackendWithRetry()
        }

        // Step 3: Delayed systems (need backend or time to settle)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            KairoMorningBriefing.shared.startListening()
            KairoAppController.shared.checkAndRequestAutomation()
        }

        // Voice activation observers
        NotificationCenter.default.addObserver(forName: .kairoVoiceActivated, object: nil, queue: .main) { [weak self] _ in
            self?.vm.open()
        }
        NotificationCenter.default.addObserver(forName: .kairoVoiceDismissed, object: nil, queue: .main) { [weak self] _ in
            self?.closeNotchTask?.cancel()
            self?.closeNotchTask = Task {
                do {
                    try await Task.sleep(for: .seconds(10))
                    await MainActor.run { self?.vm.close() }
                } catch {}
            }
        }
    }

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        // Bundle ships `kairo.m4a` (renamed from boringNotch on rebrand);
        // the previous filename `kairo_welcome.m4a` doesn't exist and
        // would crash here when force-unwrapped on first launch.
        audioPlayer.play(fileName: "kairo", fileExtension: "m4a")
    }

    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }

    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in windows.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    windows.removeValue(forKey: uuid)
                    viewModels.removeValue(forKey: uuid)
                }
            }

            // Create or update windows for all screens
            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }
                
                if windows[uuid] == nil {
                    let viewModel = KairoViewModel(screenUUID: uuid)
                    let window = createKairoWindow(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)

                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screen(withUUID: coordinator.preferredScreenUUID ?? "") {
                coordinator.selectedScreenUUID = coordinator.preferredScreenUUID ?? ""
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main,
                      let mainUUID = mainScreen.displayUUID {
                coordinator.selectedScreenUUID = mainUUID
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }

            vm.screenUUID = selectedScreen.displayUUID
            vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)

            if window == nil {
                window = createKairoWindow(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Onboarding"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    step: step,
                    onFinish: {
                        window.orderOut(nil)
//                        NSApp.setActivationPolicy(.accessory)
                        window.close()
                        NSApp.deactivate()
                    },
                    onOpenSettings: {
                        window.close()
                        SettingsWindowController.shared.showWindow()
                    }
                ))
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            onboardingWindowController = NSWindowController(window: window)
        }

//        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}
