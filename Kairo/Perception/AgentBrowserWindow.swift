//
//  AgentBrowserWindow.swift
//  Kairo — in-app premium browser that the agent uses for research
//
//  Why this exists:
//   - Previously, when the user asked Kairo to "find me hotels nearby",
//     the model would often fall through to `system → open_app Chrome`,
//     which made Chrome pop up — but the agent never read the page,
//     never synthesized, never proposed an action. Just a dumb redirect.
//   - With AgentBrowserWindow + BrowseTool, the model now loads pages
//     IN-APP. The user SEES the pages being read (HUD-styled WKWebView
//     window with the cyan bracket + scan-line treatment). The
//     extracted text feeds back to the LLM which synthesizes a real
//     answer.
//
//  Lifecycle:
//   - Singleton, lazy. Window is created on first `load()`.
//   - Window stays open after a load completes so the user sees the
//     last page browsed. Auto-fades after 60s of inactivity, or on
//     explicit `hide()` / Esc.
//   - Always-on-top, ignores app focus changes.
//

import AppKit
import SwiftUI
import WebKit

@MainActor
final class KairoAgentBrowser: NSObject {
    static let shared = KairoAgentBrowser()

    private var window: NSPanel?
    private var hostingView: NSHostingView<AgentBrowserView>?
    private let viewState = AgentBrowserState()
    private var hideTask: Task<Void, Never>?

    private override init() {}

    // MARK: - Public API

    /// Load a URL in the agent browser. Returns the extracted plain-text
    /// content of the page (truncated to ~6KB) once the page has finished
    /// loading + DOMContentLoaded + a short settle. The window appears
    /// on first call and remains visible for ~60 seconds after the last
    /// browse — so the user can see what the agent just looked at.
    ///
    /// Throws if the URL is bad or the page fails to load.
    func load(url: URL, maxChars: Int = 6000) async throws -> String {
        ensureWindow()
        cancelAutoHide()
        showWindow()

        viewState.urlString = url.absoluteString
        viewState.host = url.host ?? ""
        viewState.status = .loading
        viewState.progressLabel = "Loading"

        let html = try await viewState.coordinator.load(url: url)
        viewState.status = .extracting
        viewState.progressLabel = "Reading"

        // Brief settle for SPA hydration / lazy content
        try? await Task.sleep(for: .milliseconds(400))

        let text = try await viewState.coordinator.extractText()
        viewState.status = .idle
        viewState.progressLabel = "Read \(text.count) chars"
        viewState.lastPreview = String(text.prefix(180))

        scheduleAutoHide(after: 60)

        // Cap output for the LLM context
        let scoped = text.count > maxChars
            ? String(text.prefix(maxChars)) + " …(truncated)"
            : text
        return scoped
    }

    /// Force-show the window without loading. Useful if the agent wants
    /// to surface the previous page again.
    func show() {
        ensureWindow()
        showWindow()
        cancelAutoHide()
    }

    /// Force-hide.
    func hide() {
        cancelAutoHide()
        guard let panel = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.window?.orderOut(nil) }
        })
    }

    // MARK: - Window

    private func ensureWindow() {
        if window != nil { return }

        let view = AgentBrowserView(state: viewState)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 650)

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = visible.midX - 450
        let y = visible.midY - 325

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: 900, height: 650),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = host

        self.hostingView = host
        self.window = panel
    }

    private func showWindow() {
        guard let panel = window else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
    }

    private func scheduleAutoHide(after seconds: TimeInterval) {
        cancelAutoHide()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.hide() }
        }
    }

    private func cancelAutoHide() {
        hideTask?.cancel()
        hideTask = nil
    }
}

// MARK: - View state

@MainActor
final class AgentBrowserState: ObservableObject {
    enum Status { case idle, loading, extracting }

    @Published var urlString: String = ""
    @Published var host: String = ""
    @Published var status: Status = .idle
    @Published var progressLabel: String = ""
    @Published var lastPreview: String = ""

    let coordinator = WebKitCoordinator()
}

// MARK: - WKWebView coordinator
//
// Owns the WKWebView. Exposes async `load(url:)` and `extractText()` to
// AgentBrowserState. Hides the noisy WKWebView delegate plumbing.

@MainActor
final class WebKitCoordinator: NSObject, ObservableObject {
    let webView: WKWebView

    private var loadContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 Kairo/1.0"
        view.setValue(false, forKey: "drawsBackground")
        self.webView = view
        super.init()
        view.navigationDelegate = self
    }

    /// Loads a URL and resolves when the page's main frame finishes loading.
    func load(url: URL) async throws -> Void {
        // Stop any in-flight load
        if webView.isLoading {
            webView.stopLoading()
            loadContinuation?.resume(throwing: CancellationError())
            loadContinuation = nil
        }

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.loadContinuation = cont
            webView.load(request)
        }
    }

    /// Pulls readable plain text out of the page. Prefers <article> →
    /// <main> → document.body, then collapses whitespace.
    func extractText() async throws -> String {
        let js = """
        (function() {
          const root = document.querySelector('article')
                    || document.querySelector('main')
                    || document.body;
          if (!root) return '';
          // Skip script/style nodes by relying on innerText (browser handles it).
          let t = root.innerText || '';
          // Light whitespace cleanup
          t = t.replace(/[\\t ]+/g, ' ').replace(/\\n{3,}/g, '\\n\\n').trim();
          return t;
        })();
        """
        let result = try await webView.evaluateJavaScript(js)
        return (result as? String) ?? ""
    }
}

// MARK: - Navigation delegate — resolves the load continuation

extension WebKitCoordinator: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.loadContinuation?.resume(returning: ())
            self.loadContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.loadContinuation?.resume(throwing: error)
            self.loadContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.loadContinuation?.resume(throwing: error)
            self.loadContinuation = nil
        }
    }
}

// MARK: - Premium SwiftUI shell around the WKWebView

struct AgentBrowserView: View {
    @ObservedObject var state: AgentBrowserState

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return ZStack(alignment: .topTrailing) {
            // Background: dark glass + scan lines
            ZStack {
                shape.fill(Color.black.opacity(0.78))
                shape.fill(.regularMaterial)
                HUDScanLines(spacing: 4, opacity: 0.025, sweepOpacity: 0.04, sweepPeriod: 6.0)
                    .clipShape(shape)
            }

            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().background(HUDPalette.primary.opacity(0.18))
                WebViewHost(webView: state.coordinator.webView)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                footer
            }
        }
        .overlay {
            Color.clear.modifier(HUDRimGlow(color: HUDPalette.primary, thickness: 1, radius: 18, period: 5.0))
        }
        .overlay {
            HUDBrackets(color: HUDPalette.primary, thickness: 1, length: 14, inset: 6)
        }
        .shadow(color: HUDPalette.primary.opacity(0.30), radius: 18, x: 0, y: 0)
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 12)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Kairo.Space.sm) {
            Text("◆ KAIRO · BROWSER")
                .font(Kairo.Typography.captionStrong.monospaced())
                .tracking(1.8)
                .foregroundStyle(HUDPalette.primary)
            Text("·").foregroundStyle(HUDPalette.primary.opacity(0.4))
            Text(state.host.isEmpty ? "—" : state.host.uppercased())
                .font(Kairo.Typography.monoSmall)
                .tracking(1)
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
            Spacer()
            statusPill
            closeButton
        }
        .padding(.horizontal, Kairo.Space.lg)
        .padding(.top, Kairo.Space.md)
        .padding(.bottom, Kairo.Space.sm)
    }

    private var statusPill: some View {
        let (label, color): (String, Color) = {
            switch state.status {
            case .idle:       return ("READY", HUDPalette.primary.opacity(0.5))
            case .loading:    return ("LOADING", HUDPalette.primary)
            case .extracting: return ("READING", HUDPalette.accent2)
            }
        }()
        return HStack(spacing: Kairo.Space.xs) {
            Circle().fill(color).frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.8), radius: 4)
            Text(label)
                .font(Kairo.Typography.monoSmall)
                .tracking(1.2)
                .foregroundStyle(color)
        }
        .padding(.horizontal, Kairo.Space.sm)
        .padding(.vertical, Kairo.Space.xxs + 1)
        .background(Capsule(style: .continuous).fill(color.opacity(0.15)))
        .overlay(Capsule(style: .continuous).strokeBorder(color.opacity(0.4), lineWidth: 0.5))
    }

    private var closeButton: some View {
        Button {
            KairoAgentBrowser.shared.hide()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(HUDPalette.primary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(HUDPalette.primary.opacity(0.1)))
                .overlay(Circle().strokeBorder(HUDPalette.primary.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Kairo.Space.sm) {
            Text("URL")
                .font(Kairo.Typography.monoSmall)
                .tracking(1.2)
                .foregroundStyle(HUDPalette.primary.opacity(0.5))
            Text(state.urlString)
                .font(Kairo.Typography.monoSmall)
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(state.progressLabel)
                .font(Kairo.Typography.monoSmall)
                .foregroundStyle(HUDPalette.primary.opacity(0.7))
        }
        .padding(.horizontal, Kairo.Space.lg)
        .padding(.bottom, Kairo.Space.md)
    }
}

// MARK: - WKWebView bridge (NSViewRepresentable)

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
