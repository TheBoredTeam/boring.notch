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
    // Connection management (Composio v3 SDK) — see ComposioConnectionManager.
    let items: [PiConnectionItem]?   // "connections"
    let defaults: [String: String]?  // "connections" — file-sourced default account per toolkit
    let alias: String?               // "connection_expired"
    let connectedAccountId: String?  // "connection_expired"
    let userId: String?              // "connection_expired"
    let status: String?              // "connection_expired"
    let url: String?                 // "connection_link"
}

/// One connected account row from the sidecar's `connections` event.
struct PiConnectionItem: Codable, Equatable {
    let toolkit: String
    let alias: String?
    let wordId: String?  // Composio human word id — selector fallback after alias
    let connectedAccountId: String
    let authConfigId: String?
    let status: String
    let logo: String?   // resolved from Composio toolkit metadata (meta.logo)
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
    /// True when `toolkitPalette` is a curated override published RAW (mockup stops,
    /// per-stop weight packed into each color's alpha). The peek aurora reads this to
    /// skip `deepen()` and honor weights so the in-app render copies the manifest mockup.
    @Published private(set) var toolkitPaletteIsRaw: Bool = false
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
            flushPendingMessages()
            // Push default aliases + pull the initial connection inventory now that
            // stdin is wired (sidecar also auto-reconciles on its own startup).
            ComposioConnectionManager.shared.sidecarDidLaunch()
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

    // MARK: - Connection management commands (Composio)

    /// Control messages queued before stdin is wired (e.g. default aliases sent at
    /// launch). Flushed in order the moment the sidecar process is up.
    private var pendingMessages: [[String: Any]] = []

    /// Ask the sidecar to (re)list connected accounts. The reply arrives as a
    /// `connections` event, forwarded to `ComposioConnectionManager`. Lazily launches.
    func requestConnections() {
        start()
        writeOrQueue(["type": "list_connections"])
    }

    /// Kick off hosted re-auth for a toolkit/account; the sidecar replies with a
    /// `connection_link` the caller opens in the browser.
    func reconnect(connectedAccountId: String? = nil, toolkit: String? = nil) {
        start()
        var msg: [String: Any] = ["type": "reconnect"]
        if let connectedAccountId { msg["connectedAccountId"] = connectedAccountId }
        if let toolkit { msg["toolkit"] = toolkit }
        writeOrQueue(msg)
    }

    /// Authorize a NEW account for a toolkit, out of band (no agent involvement). The
    /// sidecar replies with a `connection_link` the caller opens in the browser — the
    /// same clean path as `reconnect`, so it can never put an auth URL in the transcript.
    func connect(toolkit: String, alias: String? = nil) {
        start()
        var msg: [String: Any] = ["type": "connect", "toolkit": toolkit.lowercased()]
        if let alias, !alias.isEmpty { msg["alias"] = alias }
        writeOrQueue(msg)
    }

    /// Set (or, with an empty selector, clear → Automatic) the default account for a
    /// toolkit. The sidecar writes it to the extension config file (the agent's source
    /// of truth) and re-emits `connections` so the UI ★ reflects the file.
    func setDefaultAccount(toolkit: String, selector: String) {
        start()
        writeOrQueue(["type": "set_default", "toolkit": toolkit.lowercased(), "selector": selector])
    }

    /// Set (or, with an empty alias, clear) the human-readable alias for a connected
    /// account. The sidecar writes it through `connectedAccounts.update` and re-emits
    /// `connections` so the row relabels.
    func renameConnection(connectedAccountId: String, alias: String) {
        start()
        writeOrQueue(["type": "rename_connection", "connectedAccountId": connectedAccountId, "alias": alias])
    }

    /// Permanently disconnect a connected account. The sidecar deletes it and re-emits
    /// `connections` so the row drops.
    func deleteConnection(connectedAccountId: String) {
        start()
        writeOrQueue(["type": "delete_connection", "connectedAccountId": connectedAccountId])
    }

    private func writeOrQueue(_ object: [String: Any]) {
        if stdinHandle == nil {
            pendingMessages.append(object)
        } else {
            write(object)
        }
    }

    private func flushPendingMessages() {
        guard stdinHandle != nil, !pendingMessages.isEmpty else { return }
        let queued = pendingMessages
        pendingMessages = []
        for msg in queued { write(msg) }
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
            toolkitPalette = []
            toolkitPaletteIsRaw = false
            if statusWord != "aborted" { statusWord = "done" }
            // Show "✓ Done" briefly, then auto-hide. The peek is only rendered while
            // the notch is collapsed and the Pi tab is active, so when the panel is
            // open this is a no-op; when collapsed, the peek confirms completion and
            // gets out of the way instead of squatting next to the notch forever.
            BoringViewCoordinator.shared.showPiPeek()
            BoringViewCoordinator.shared.schedulePiPeekHide(after: 3)

        // MARK: Connection management (forwarded to ComposioConnectionManager)

        case "connections":
            ComposioConnectionManager.shared.applyConnections(event.items ?? [], defaults: event.defaults)

        case "connection_expired":
            if let toolkit = event.toolkit, let id = event.connectedAccountId {
                ComposioConnectionManager.shared.markReauthNeeded(
                    toolkit: toolkit,
                    alias: event.alias,
                    connectedAccountId: id,
                    status: event.status ?? "EXPIRED"
                )
            }

        case "connection_link":
            if let raw = event.url, let url = URL(string: raw) {
                ComposioConnectionManager.shared.openConnectionLink(url)
            }

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
        // Special case: the generic Composio meta-ops (`composio_search_tools`,
        // `composio_get_tool_schemas`) carry the slug "composio" and a CDN "composio"
        // logo. That isn't a branded toolkit, so don't paint CDN art — clear the logo
        // (and the brand palette) so the peek renders its bundled white-tinted Composio
        // mark (PiAgentView.logo fallback) and the panel aurora stays neutral.
        if slug == "composio" {
            toolkitLogo = nil
            toolkitAccent = nil
            toolkitPalette = []
            toolkitPaletteIsRaw = false
            return
        }
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
    ///   2. Curated override (`brandColorOverrides`, from `BrandPalettes.json`) — an
    ///      intentional allowlist published RAW (no `legibleTint`): the stops are
    ///      hand-picked to read on black, so tinting would only mute them to pastel.
    ///      Wins over SVG extraction for any listed slug.
    ///   3. SVG `fill=` metadata — the exact brand hex, no bitmap allocation. Tinted,
    ///      then run through the 3-case saturation gate (≥2 saturated → rich; 1 → that
    ///      hue; 0 → indigo).
    ///   4. Raster histogram on the rendered image — robustness for any non-SVG (PNG)
    ///      logo, or a memory-cache hit whose palette wasn't memoized.
    private func derivePalette(slug: String, svgData: Data?, fallbackImage: NSImage) {
        // 1. Memo hit. The cache stores colors but not rawness — recompute it from the
        // allowlist so a cached override still publishes with the raw flag set.
        if let cached = paletteCache[slug] {
            publishPalette(cached, slug: slug, raw: Self.brandColorOverrides[slug] != nil)
            return
        }

        // 2. Curated allowlist wins, rendered RAW (already-legible, hand-picked stops).
        if let override = Self.brandColorOverrides[slug], !override.isEmpty {
            publishPalette(override, slug: slug, raw: true)
            return
        }

        // 3. Real SVG brand colors (tinted + gated).
        if let svgData {
            let brand = NSImage.brandColorsFromSVG(svgData, max: 4)
            if !brand.isEmpty {
                publishPalette(Self.gatedPalette(from: brand.map { Self.legibleTint($0) }), slug: slug)
                return
            }
        }

        // 4. Raster histogram → gate → indigo fallback. Graceful degradation for any
        // non-SVG logo or a monochrome mark that isn't curated.
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
    private func publishPalette(_ palette: [NSColor], slug: String, raw: Bool = false) {
        paletteCache[slug] = palette
        toolkitPalette = palette
        // A raw override may pack a per-stop weight into the first stop's alpha; force it
        // opaque so a weighted first stop can't wash the thinking-bars/wave tint.
        toolkitAccent = palette.first?.withAlphaComponent(1)
        toolkitPaletteIsRaw = raw
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

    /// Tiny `#RRGGBB` → NSColor helper for the curated defaults (delegates to the SVG
    /// parser's hex decode). The literals here are known-valid, so a failed parse is a
    /// programmer error — fall back to mid-grey rather than crash.
    private static func hex(_ s: String) -> NSColor {
        NSImage.colorFromHex(s) ?? NSColor(white: 0.5, alpha: 1)
    }

    /// Parse a curated JSON stop: "#RRGGBB" or "#RRGGBB*0.55". The optional `*weight`
    /// suffix (0–1) is packed into the returned color's ALPHA channel — the aurora reads
    /// that alpha as a radius+opacity multiplier (the mockup's per-stop weight), not as
    /// real transparency. Only the curated path uses this; `NSImage.colorFromHex` (shared
    /// with the SVG `fill=` parser) is left untouched.
    private static func weightedColorFromHex(_ s: String) -> NSColor? {
        let parts = s.split(separator: "*", maxSplits: 1, omittingEmptySubsequences: false)
        guard let base = NSImage.colorFromHex(String(parts[0]))?.usingColorSpace(.sRGB) else { return nil }
        let w = max(0, min(1, parts.count == 2 ? CGFloat(Double(parts[1]) ?? 1) : 1))
        return NSColor(srgbRed: base.redComponent, green: base.greenComponent, blue: base.blueComponent, alpha: w)
    }

    /// One entry in `BrandPalettes.json`: a list of `#RRGGBB` stops. The JSON also
    /// carries a human `note` per entry; it's documentation-only, so the decoder ignores
    /// it (unknown keys are skipped).
    private struct BrandPaletteEntry: Decodable {
        let stops: [String]
    }

    /// Top level of `BrandPalettes.json`. `version` is reserved for future migrations
    /// (decoded optionally; not gated on today).
    private struct BrandManifest: Decodable {
        let version: Int?
        let palettes: [String: BrandPaletteEntry]
    }

    /// Compiled fallback for the two original curated brands, so notion+github still
    /// render even if the bundled JSON is missing or corrupt. The JSON wins on conflict
    /// (see `brandColorOverrides`); the nine newer brands are JSON-only.
    private static let compiledDefaults: [String: [NSColor]] = [
        "notion": [hex("#C9C7C1"), hex("#8C8A85")],   // warm Notion graphite glow
        "github": [hex("#212183"), hex("#000000")],   // octocat indigo grounded to black (matches JSON)
    ]

    /// Curated brand gradients, keyed by lowercase toolkit slug. This is an intentional
    /// allowlist: a listed slug always renders these hand-picked, already-legible stops
    /// *raw* (no `legibleTint`), overriding its automatic SVG/raster palette. Source of
    /// truth is the version-controlled `Resources/BrandPalettes.json` — edit + push to add
    /// or tune a brand, no recompile. Compiled defaults are merged underneath as a
    /// resilience floor; JSON is authoritative on conflict.
    private static let brandColorOverrides: [String: [NSColor]] = {
        var table = compiledDefaults
        table.merge(loadBrandPalettes()) { _, json in json }
        return table
    }()

    /// Decode `BrandPalettes.json` from the app bundle into `[slug: [NSColor]]`. Any
    /// failure (missing bundle, unreadable, undecodable) yields an empty table so the
    /// compiled defaults still apply. Keys are lowercased; an entry whose stops all fail
    /// to parse is dropped rather than published empty.
    private static func loadBrandPalettes() -> [String: [NSColor]] {
        guard let url = Bundle.main.url(forResource: "BrandPalettes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(BrandManifest.self, from: data)
        else { return [:] }
        return manifest.palettes.reduce(into: [:]) { acc, kv in
            let colors = kv.value.stops.compactMap(weightedColorFromHex)
            if !colors.isEmpty { acc[kv.key.lowercased()] = colors }
        }
    }
}
