//
//  PiAgentManager.swift
//  boringNotch
//
//  Drives the bundled `pi-sidecar` binary and streams its work into the notch the
//  same way NowPlayingController streams a song. Owns the child Process, writes
//  prompts/aborts to its stdin, and decodes the newline-JSON wire protocol off its
//  stdout into @Published state the Pi tab + peek render.
//

import AppKit
import Combine
import Foundation

/// One line of the sidecar's wire protocol. Fields are optional because the
/// protocol is a tagged union keyed on `type`.
struct PiEvent: Codable {
    let type: String
    let word: String?
    let delta: String?
    let id: String?
    let tool: String?
    let toolkit: String?
    let logo: String?
    let ok: Bool?
    let message: String?
}

/// A single tool invocation shown as a chip in the expanded Pi tab.
struct ToolChip: Identifiable, Equatable {
    let id: String        // sidecar toolCallId
    let tool: String      // full tool name, e.g. GMAIL_SEND_EMAIL
    let toolkit: String   // slug, e.g. gmail
    let logo: String?     // Composio CDN URL
    var running: Bool
    var ok: Bool?
}

@MainActor
final class PiAgentManager: ObservableObject {
    static let shared = PiAgentManager()

    // MARK: Published UI state
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var statusWord: String = ""
    @Published private(set) var toolkitLogo: NSImage?
    @Published private(set) var currentTool: String?
    @Published private(set) var chips: [ToolChip] = []
    @Published private(set) var transcript: String = ""
    @Published private(set) var lastError: String?

    // MARK: Process plumbing
    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var stdinHandle: FileHandle?
    private var streamTask: Task<Void, Never>?
    private var didLaunch = false
    /// A prompt issued before the sidecar finished launching; flushed once stdin is ready.
    private var pendingPrompt: String?

    // MARK: Logo cache
    private let logoMemoryCache = NSCache<NSString, NSImage>()
    private let logoDiskDir: URL = {
        let dir = temporaryDirectory.appendingPathComponent("PiToolkitLogos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    // MARK: - Lifecycle

    /// Launch the sidecar (idempotent). Called lazily on the first prompt so we don't
    /// spawn a ~70 MB process until the user actually asks Pi something.
    func start() {
        guard !didLaunch else { return }
        didLaunch = true

        guard let exe = Bundle.main.url(forResource: "pi-sidecar", withExtension: "") else {
            lastError = "pi-sidecar binary missing from app bundle. Run `make sidecar`."
            didLaunch = false
            return
        }

        Task { await launch(exe: exe) }
    }

    private func launch(exe: URL) async {
        let process = Process()
        process.executableURL = exe
        // Inherit env (HOME) so the sidecar reuses ~/.pi & ~/.composio CLI login.

        let stdin = Pipe()
        let reader = JSONLinesPipeHandler()
        process.standardInput = stdin
        process.standardOutput = await reader.getPipe()
        // Leave standardError inheriting the app's stderr for debugging.

        self.process = process
        self.stdinHandle = stdin.fileHandleForWriting
        self.pipeHandler = reader

        do {
            try process.run()
            streamTask = Task { [weak self] in
                guard let handler = await self?.pipeHandler else { return }
                await handler.readJSONLines(as: PiEvent.self) { [weak self] event in
                    await self?.handle(event)
                }
            }
            flushPendingPrompt()
        } catch {
            lastError = "Failed to launch pi-sidecar: \(error.localizedDescription)"
            didLaunch = false
        }
    }

    /// Tear down the child process. Called from the AppDelegate on terminate.
    func destroy() {
        streamTask?.cancel()
        streamTask = nil

        if let pipeHandler {
            Task { await pipeHandler.close() }
        }
        try? stdinHandle?.close()

        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        self.process = nil
        self.pipeHandler = nil
        self.stdinHandle = nil
        self.didLaunch = false
    }

    // MARK: - Commands

    /// Send a prompt. Resets the run's transcript/chips, marks running, and shows the
    /// peek so a mouse-away collapses to the streaming live-activity.
    func send(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        start()

        transcript = ""
        chips = []
        currentTool = nil
        lastError = nil
        statusWord = "thinking"
        isRunning = true
        BoringViewCoordinator.shared.showPiPeek()

        // The sidecar launches asynchronously; if stdin isn't wired yet, hold the
        // prompt and flush it the moment the process is up.
        pendingPrompt = text
        flushPendingPrompt()
    }

    private func flushPendingPrompt() {
        guard let text = pendingPrompt, stdinHandle != nil else { return }
        pendingPrompt = nil
        write(["type": "prompt", "text": text])
    }

    /// Abort the current run (⌘.).
    func abort() {
        guard isRunning else { return }
        write(["type": "abort"])
    }

    private func write(_ object: [String: Any]) {
        guard let stdinHandle else { return }
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A) // newline
        do {
            try stdinHandle.write(contentsOf: data)
        } catch {
            lastError = "Lost connection to pi-sidecar."
            isRunning = false
        }
    }

    // MARK: - Event handling

    private func handle(_ event: PiEvent) {
        switch event.type {
        case "ready":
            break

        case "status":
            if let word = event.word { statusWord = word }

        case "text_delta":
            if let delta = event.delta { transcript += delta }

        case "tool_start":
            let id = event.id ?? UUID().uuidString
            currentTool = event.tool
            if let word = event.word { statusWord = word }
            let chip = ToolChip(
                id: id,
                tool: event.tool ?? "tool",
                toolkit: event.toolkit ?? (event.word ?? ""),
                logo: event.logo,
                running: true,
                ok: nil
            )
            chips.append(chip)
            if let logo = event.logo {
                loadLogo(from: logo, slug: chip.toolkit)
            }

        case "tool_end":
            if let id = event.id, let idx = chips.firstIndex(where: { $0.id == id }) {
                chips[idx].running = false
                chips[idx].ok = event.ok ?? true
            }

        case "error":
            lastError = event.message ?? "Pi encountered an error."

        case "done":
            isRunning = false
            currentTool = nil
            if statusWord != "aborted" { statusWord = "done" }
            BoringViewCoordinator.shared.schedulePiPeekHide()

        default:
            break
        }
    }

    // MARK: - Toolkit logos (cached like album art)

    private func loadLogo(from urlString: String, slug: String) {
        let key = slug as NSString
        if let cached = logoMemoryCache.object(forKey: key) {
            toolkitLogo = cached
            return
        }

        let diskURL = logoDiskDir.appendingPathComponent(slug + ".png")
        if let data = try? Data(contentsOf: diskURL), let image = NSImage(data: data) {
            logoMemoryCache.setObject(image, forKey: key)
            toolkitLogo = image
            return
        }

        guard let url = URL(string: urlString) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            try? data.write(to: diskURL)
            await MainActor.run {
                guard let self else { return }
                self.logoMemoryCache.setObject(image, forKey: key)
                // Only adopt if this is still (or again) the active toolkit.
                if self.currentTool != nil || self.toolkitLogo == nil {
                    self.toolkitLogo = image
                }
            }
        }
    }
}
