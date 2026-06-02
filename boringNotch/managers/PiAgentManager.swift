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
    let index: Int?
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
    /// The active tool's name, sanitized for display ("Send email", "Execute tool").
    @Published private(set) var currentToolPretty: String?
    /// Flair color sampled from the active toolkit's logo (gmail red, calendar blue, …).
    /// Lightened for legible text/tint. Nil → callers fall back to the app accent.
    @Published private(set) var toolkitAccent: NSColor?
    @Published private(set) var chips: [ToolChip] = []
    @Published private(set) var transcript: String = ""
    @Published private(set) var lastError: String?

    /// A tool call the model is still streaming arguments for (sidecar `tool_forming`).
    /// Sanitized for display ("Send email"); nil when no name is known yet but a call
    /// is forming → callers show a generic "Calling a tool…" shimmer.
    @Published private(set) var formingToolPretty: String?
    /// Toolkit slug of the forming tool (gmail, googlecalendar, …); nil until known.
    @Published private(set) var formingToolkit: String?
    /// True from `tool_forming` until the next `tool_start`/`done` — drives shimmer.
    @Published private(set) var isForming: Bool = false

    /// Session pin: keeps the open Pi panel from collapsing on un-hover and makes the
    /// swipe-up close inert, so reading/scrolling a streamed answer can never dismiss
    /// the panel. Runtime-only (never persisted) — cleared by unpin, tab switch,
    /// panel close, and app restart.
    @Published var piPinned: Bool = false

    /// Natural height of the Pi tab's content, reported up from PiAgentView via a
    /// PreferenceKey. BoringViewModel clamps this into `openPanelHeight` so the panel
    /// grows with the answer instead of being a fixed box.
    @Published var measuredContentHeight: CGFloat = 0

    /// Backs the prompt field so typed text survives collapse/expand and feeds the
    /// hover-hold condition. Lifted out of `PiAgentView`'s `@State`.
    @Published var draft: String = ""

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
        // Inherit env (HOME) so the sidecar reuses ~/.pi & ~/.composio CLI login,
        // but fix up PATH: GUI apps launch with launchd's bare PATH
        // (/usr/bin:/bin:/usr/sbin:/sbin), so the sidecar's `npm root -g` (and any
        // CLI it shells out to) fails with "Executable not found in $PATH" unless
        // the standard user tool directories are added.
        process.environment = Self.sidecarEnvironment()

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

    /// The app's environment with PATH augmented by the common user tool
    /// directories (node/npm/bun/composio installs). Finder, Dock, and `open`
    /// launches only get launchd's bare PATH, which has none of them.
    private static func sidecarEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/share/fnm/aliases/default/bin", // fnm's stable default node
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.bun/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/Library/pnpm",
            "\(home)/.composio",
        ].filter { FileManager.default.fileExists(atPath: $0) }

        let inherited = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":").map(String.init)
        var seen = Set<String>()
        env["PATH"] = (candidates + inherited)
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
        return env
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
        currentToolPretty = nil
        clearFormingState()
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

        case "tool_forming":
            // The model committed to a tool call but is still streaming its arguments.
            // Surface it immediately (shimmer) instead of leaving "Thinking…" up.
            isForming = true
            formingToolPretty = event.tool.map(Self.prettyToolName)
            formingToolkit = event.toolkit
            if let logo = event.logo, let toolkit = event.toolkit {
                loadLogo(from: logo, slug: toolkit)
            }
            BoringViewCoordinator.shared.showPiPeek()

        case "tool_start":
            let id = event.id ?? UUID().uuidString
            // The forming phase resolved into a real execution — hand off to the chip.
            clearFormingState()
            currentTool = event.tool
            currentToolPretty = event.tool.map(Self.prettyToolName)
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
            currentToolPretty = nil
            clearFormingState()
            // Return to base: drop the last tool's colored logo/accent so the peek
            // falls back to the bundled Composio mark instead of squatting on it.
            toolkitLogo = nil
            toolkitAccent = nil
            if statusWord != "aborted" { statusWord = "done" }
            // Show "✓ Done" briefly, then auto-hide. The peek is only rendered while
            // the notch is collapsed and the Pi tab is active, so when the panel is
            // open this is a no-op; when collapsed, the peek confirms completion and
            // gets out of the way instead of squatting next to the notch forever.
            BoringViewCoordinator.shared.showPiPeek()
            BoringViewCoordinator.shared.schedulePiPeekHide(after: 3)

        default:
            break
        }
    }

    /// Forget any in-flight `tool_forming` state (run boundary, tool resolved, done).
    private func clearFormingState() {
        isForming = false
        formingToolPretty = nil
        formingToolkit = nil
    }

    // MARK: - Tool name display

    /// Turn a raw Composio tool name into something human ("Send email").
    /// Drops the first `_`-segment (the toolkit slug, matching `sidecar`'s
    /// `toolkitSlug`), joins the rest with spaces, and sentence-cases the result.
    /// `GMAIL_SEND_EMAIL → "Send email"`, `composio_execute_tool → "Execute tool"`,
    /// `composio_get_tool_schemas → "Get tool schemas"`.
    static func prettyToolName(_ raw: String) -> String {
        let parts = raw.split(separator: "_").map(String.init)
        // Drop the toolkit slug. If there's only one segment, keep it as-is.
        let rest = parts.count > 1 ? Array(parts.dropFirst()) : parts
        let joined = rest.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let base = joined.isEmpty ? raw : joined
        let lowered = base.lowercased()
        guard let first = lowered.first else { return base }
        return first.uppercased() + lowered.dropFirst()
    }

    // MARK: - Toolkit logos (cached like album art)

    private func loadLogo(from urlString: String, slug: String) {
        let key = slug as NSString
        if let cached = logoMemoryCache.object(forKey: key) {
            adoptLogo(cached, slug: slug)
            return
        }

        let diskURL = logoDiskDir.appendingPathComponent(slug + ".png")
        if let data = try? Data(contentsOf: diskURL), let image = NSImage(data: data) {
            logoMemoryCache.setObject(image, forKey: key)
            adoptLogo(image, slug: slug)
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
                    self.adoptLogo(image, slug: slug)
                }
            }
        }
    }

    /// Publish a toolkit logo and sample its flair color (lightened for legibility).
    /// The color follows whichever toolkit is active — gmail red, calendar blue, etc.
    /// The Composio mark is monochrome, so it averages to a neutral light gray
    /// (averageColor floors near-black to min brightness), which is honest to the mark.
    private func adoptLogo(_ image: NSImage, slug: String) {
        toolkitLogo = image
        image.averageColor { [weak self] color in
            // averageColor already hops back to the main queue.
            guard let self, let color else { return }
            self.toolkitAccent = Self.legibleTint(color)
        }
    }

    /// Mix a sampled color toward white so it stays readable as text/wave tint on
    /// the black notch (mirrors the mockup's `lighten`).
    private static func legibleTint(_ color: NSColor, amount: CGFloat = 0.45) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return color }
        let r = rgb.redComponent + (1 - rgb.redComponent) * amount
        let g = rgb.greenComponent + (1 - rgb.greenComponent) * amount
        let b = rgb.blueComponent + (1 - rgb.blueComponent) * amount
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
