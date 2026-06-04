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
    let app: String?
    let url: String?
    let alias: String?
}

struct ConnectionPrompt: Equatable {
    let app: String
    let url: URL
    let alias: String?
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
    /// Area-weighted dominant colors of the active toolkit's logo (gmail's red/blue/
    /// green/yellow, calendar blue, …), each lightened for legibility. Drives the peek
    /// aurora's multi-color mesh. Empty for a monochrome mark → callers fall back to a
    /// single indigo. `toolkitAccent` mirrors `toolkitPalette.first` for back-compat.
    @Published private(set) var toolkitPalette: [NSColor] = []
    @Published private(set) var chips: [ToolChip] = []
    @Published private(set) var transcript: String = ""
    @Published private(set) var connectionPrompt: ConnectionPrompt?
    @Published private(set) var lastError: String?

    /// Connection deeplinks surfaced this turn (from `connection_required`). The CTA
    /// capsule is the only place these should appear — `displayTranscript` strips them
    /// out of the rendered prose so they never show inline (and never repeat).
    private var connectionDeeplinks: Set<String> = []

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

    /// Memoized publish-tinted palettes keyed by slug. Populated on first derive, read
    /// first on every subsequent derive (including the memory-image-cache path that
    /// holds no raw SVG bytes). Never cleared on `done` — a pure slug→colors memo, so
    /// re-running the same toolkit paints instantly without re-parsing.
    private var paletteCache: [String: [NSColor]] = [:]

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
        connectionPrompt = nil
        connectionDeeplinks = []
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
        connectionPrompt = nil
        write(["type": "abort"])
    }

    /// Hide the Composio auth CTA after the user clicks it. The CTA otherwise persists
    /// past the end of the turn (so it stays actionable) and is reset on the next turn
    /// or on abort/error. The deeplink never appears in the transcript
    /// (`displayTranscript` strips it), so dismissing the capsule removes the only place
    /// it was shown.
    func dismissConnectionPrompt() {
        connectionPrompt = nil
    }

    /// `transcript` with Composio connection deeplinks removed. Those links are
    /// surfaced by the Connect CTA capsule, so rendering them inline — often echoed
    /// several times by the model — is redundant noise. Strips both `[label](url)`
    /// markdown links and bare URLs for every connection URL seen this turn, then
    /// tidies the blank lines the removal leaves behind. No connection links → returns
    /// `transcript` untouched (the common, zero-cost case).
    var displayTranscript: String {
        guard !connectionDeeplinks.isEmpty else { return transcript }
        var text = transcript
        for url in connectionDeeplinks {
            let escaped = NSRegularExpression.escapedPattern(for: url)
            // `[any label](url)` (allow surrounding whitespace) then the bare/angle-
            // bracketed URL — order matters so the markdown wrapper goes first.
            let patterns = ["\\[[^\\]]*\\]\\(\\s*\(escaped)\\s*\\)", "<?\(escaped)>?"]
            for pattern in patterns {
                guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(text.startIndex..., in: text)
                text = re.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            }
        }
        return Self.collapseBlankLines(text)
    }

    /// Trim trailing whitespace per line and collapse runs of blank lines to one, so a
    /// stripped link doesn't leave a hole in the prose.
    private static func collapseBlankLines(_ s: String) -> String {
        var out: [String] = []
        var lastEmpty = false
        for line in s.components(separatedBy: "\n") {
            let trimmed = line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            let empty = trimmed.trimmingCharacters(in: .whitespaces).isEmpty
            if empty && lastEmpty { continue }
            out.append(trimmed)
            lastEmpty = empty
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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

        case "agent_start":
            connectionPrompt = nil
            connectionDeeplinks = []

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

        case "connection_required":
            if let app = event.app,
               let rawURL = event.url,
               let url = URL(string: rawURL) {
                connectionPrompt = ConnectionPrompt(app: app, url: url, alias: event.alias)
                connectionDeeplinks.insert(rawURL)  // strip it from the rendered prose
            }

        case "error":
            connectionPrompt = nil
            lastError = event.message ?? "Pi encountered an error."

        case "done":
            // connectionPrompt is deliberately NOT cleared here. `done` is exactly when
            // the user needs to act on the Connect CTA: the model asked them to connect
            // an app, finished its turn, and the capsule has to survive so it can be
            // clicked. It clears on the next turn (send / agent_start), on click/dismiss
            // (dismissConnectionPrompt), or on abort/error.
            isRunning = false
            currentTool = nil
            currentToolPretty = nil
            clearFormingState()
            // Return to base: drop the last tool's colored logo/accent so the peek
            // falls back to the bundled Composio mark instead of squatting on it.
            toolkitLogo = nil
            toolkitAccent = nil
            toolkitPalette = []
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
            // No raw SVG bytes on this path — derivePalette leans on `paletteCache`
            // (populated on the first in-session load) and falls back to the histogram
            // on the cached image if somehow missing.
            adoptLogo(cached, slug: slug)
            derivePalette(slug: slug, svgData: nil, fallbackImage: cached)
            return
        }

        let diskURL = logoDiskDir.appendingPathComponent(slug + ".png")
        if let data = try? Data(contentsOf: diskURL), let image = NSImage(data: data) {
            logoMemoryCache.setObject(image, forKey: key)
            adoptLogo(image, slug: slug)
            derivePalette(slug: slug, svgData: data, fallbackImage: image)
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
                    self.derivePalette(slug: slug, svgData: data, fallbackImage: image)
                }
            }
        }
    }

    /// Publish the toolkit logo for display. Color derivation is split out into
    /// `derivePalette` so the cheap SVG-metadata path can run without re-rasterizing.
    private func adoptLogo(_ image: NSImage, slug: String) {
        toolkitLogo = image
    }

    /// Resolve the active toolkit's aurora palette and publish `toolkitPalette` /
    /// `toolkitAccent`. Resolution order (lightest path first):
    ///   1. `paletteCache[slug]` — already derived this session → publish instantly.
    ///   2. SVG `fill=` metadata — the exact brand hex, no bitmap allocation. Runs the
    ///      3-case saturation gate (≥2 saturated → rich; 1 → that hue; 0 → indigo).
    ///   3. Curated override for a monochrome mark (Notion, GitHub) — published
    ///      directly, bypassing the saturation gate (a curated table is intentional,
    ///      not histogram noise).
    ///   4. Raster histogram on the rendered image — robustness for any non-SVG (PNG)
    ///      logo, or a memory-cache hit whose palette wasn't memoized.
    private func derivePalette(slug: String, svgData: Data?, fallbackImage: NSImage) {
        // 1. Memo hit.
        if let cached = paletteCache[slug] {
            publishPalette(cached, slug: slug)
            return
        }

        // 2/3. We have the raw SVG bytes: try exact brand colors, then the override.
        if let svgData {
            let brand = NSImage.brandColorsFromSVG(svgData, max: 4)
            if !brand.isEmpty {
                publishPalette(Self.gatedPalette(from: brand.map { Self.legibleTint($0) }), slug: slug)
                return
            }
            // Monochrome SVG (no real hue) → curated gradient, bypassing the gate.
            if let override = Self.brandColorOverrides[slug], !override.isEmpty {
                publishPalette(override.map { Self.legibleTint($0) }, slug: slug)
                return
            }
            // Monochrome, not yet curated → histogram (still empty → gate yields the
            // indigo fallback). Graceful degradation for unknown mono brands.
            derivePaletteFromRaster(fallbackImage, slug: slug)
            return
        }

        // No SVG bytes (memory-cache hit, memo miss): try the override, else histogram.
        if let override = Self.brandColorOverrides[slug], !override.isEmpty {
            publishPalette(override.map { Self.legibleTint($0) }, slug: slug)
            return
        }
        derivePaletteFromRaster(fallbackImage, slug: slug)
    }

    /// Raster histogram fallback: the original `dominantColors` path, kept for any logo
    /// that isn't a parseable SVG. Runs the same 3-case gate before publishing.
    private func derivePaletteFromRaster(_ image: NSImage, slug: String) {
        image.dominantColors(max: 4) { [weak self] colors in
            // dominantColors already hops back to the main queue.
            guard let self else { return }
            self.publishPalette(Self.gatedPalette(from: colors.map { Self.legibleTint($0) }), slug: slug)
        }
    }

    /// The 3-case saturation gate, shared by the SVG and raster paths. Input is already
    /// legible-tinted. ≥2 saturated hues → keep the rich palette so a near-mono mark
    /// doesn't fake a multi-color aurora; exactly 1 → keep that single hue; 0 → a
    /// legible indigo so the aurora still reads.
    private static func gatedPalette(from tinted: [NSColor]) -> [NSColor] {
        let saturated = tinted.filter { isSaturated($0) }
        if saturated.count >= 2 { return tinted }
        if saturated.count == 1 { return saturated }
        return [legibleTint(.systemIndigo)]
    }

    /// Memoize and publish a derived palette. `toolkitAccent` mirrors
    /// `toolkitPalette.first` for every existing reader.
    private func publishPalette(_ palette: [NSColor], slug: String) {
        paletteCache[slug] = palette
        toolkitPalette = palette
        toolkitAccent = palette.first
    }

    /// HSB-saturation test used to count "real" hues in a tinted palette. Tested on the
    /// *tinted* color on purpose: `legibleTint` mixes toward white, which lowers
    /// saturation, so a 0.22 threshold is calibrated for post-tint values (this is not
    /// a bug — testing the raw color would over-count washed-out grays). Lower to 0.18
    /// if too many real-colored logos fall through to the mono-indigo branch.
    private static func isSaturated(_ color: NSColor, threshold: CGFloat = 0.22) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return s >= threshold
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

    /// Tiny `#RRGGBB` → NSColor helper for the curated table (delegates to the SVG
    /// parser's hex decode). The literals here are known-valid, so a failed parse is a
    /// programmer error — fall back to mid-grey rather than crash.
    private static func hex(_ s: String) -> NSColor {
        NSImage.colorFromHex(s) ?? NSColor(white: 0.5, alpha: 1)
    }

    /// Brand gradients for monochrome toolkits whose logo SVG carries no real hue
    /// (Composio exposes no color metadata either). Seeded; tune freely. Keyed by slug.
    /// 1–2 stops each — two stops give the aurora internal depth without invoking the
    /// indigo `companionColor`. More mono slugs (x, openai, anthropic, vercel, …) can be
    /// appended as they show up.
    private static let brandColorOverrides: [String: [NSColor]] = [
        "notion": [hex("#C9C7C1"), hex("#8C8A85")],   // warm Notion graphite glow
        "github": [hex("#8B949E"), hex("#6E7681")],   // GitHub's own grey scale
    ]
}
