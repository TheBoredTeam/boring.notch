import AppKit
import ApplicationServices
import Foundation

final class AIActivityService {
    static let shared = AIActivityService()
    private let queue = DispatchQueue(label: "boringnotch.ai.state", qos: .utility)
    private var store = AIActivityStore()
    private let desktopObserver = AIActivityDesktopObserver()
    private var lastDesktopRead = Date.distantPast
    private var desktopSessions: [AIActivitySession] = []
    private var listener: AIActivitySocketListener?
    private var bridgeMessage: String?

    func snapshot(observeDesktop: Bool, frontmostBundleID: String?, reply: @escaping (Data?) -> Void) {
        queue.async { [self] in
            startBridgeIfNeeded()
            for provider in [AIProvider.codex, .claudeCode] {
                if NSRunningApplication.runningApplications(withBundleIdentifier: provider.bundleIdentifier).isEmpty {
                    store.markDesktopUnavailable(provider, at: Date())
                }
            }
            store.advance(to: Date())
            // The main app reports the frontmost app; it observes activation on a real run loop.
            store.observeFrontmost(frontmostBundleID, at: Date())
            if observeDesktop && AXIsProcessTrusted() && Date().timeIntervalSince(lastDesktopRead) >= 2 {
                let codeIsBusy = store.sessions.values.contains {
                    $0.provider == .claudeCode && $0.isDesktop && $0.status.priority >= 2
                }
                desktopSessions = desktopObserver.snapshot(excludingClaudeCode: codeIsBusy)
                lastDesktopRead = Date()
            } else if !observeDesktop || !AXIsProcessTrusted() {
                desktopObserver.reset()
                desktopSessions = []
            }
            let snapshot = AIActivitySnapshot(
                sessions: Array(store.sessions.values) + desktopSessions,
                hookConnections: Dictionary(uniqueKeysWithValues: [AIProvider.codex, .claudeCode].map {
                    ($0.rawValue, AIActivityHookInstaller.connection($0))
                }),
                accessibilityAuthorized: AXIsProcessTrusted(), desktopObservationEnabled: observeDesktop,
                bridgeReady: listener != nil, message: bridgeMessage)
            reply(try? JSONEncoder().encode(snapshot))
        }
    }

    func stop() {
        queue.async { [self] in
            listener?.stop()
            listener = nil
            desktopObserver.reset()
            desktopSessions = []
            // Old running states cannot be restored as if they were still live after disconnect.
            store = AIActivityStore()
        }
    }

    func dismiss(_ id: String) { queue.async { self.store.dismiss(id) } }

    func hookStatus(reply: @escaping (Data?) -> Void) {
        queue.async {
            let status = Dictionary(uniqueKeysWithValues: [AIProvider.codex, .claudeCode].map {
                ($0.rawValue, AIActivityHookInstaller.connection($0))
            })
            reply(try? JSONEncoder().encode(status))
        }
    }

    func configure(provider: String, remove: Bool, reply: @escaping (String) -> Void) {
        queue.async {
            guard let provider = AIProvider(rawValue: provider) else { reply("Unsupported source."); return }
            do {
                let message = try AIActivityHookInstaller.update(provider, remove: remove)
                if remove { self.store.disconnect(provider) }
                reply(message)
            }
            catch { reply(error.localizedDescription) }
        }
    }

    private func startBridgeIfNeeded() {
        if let listener, !listener.isAvailable { listener.stop(); self.listener = nil }
        guard listener == nil else { return }
        let candidate = AIActivitySocketListener { [weak self] data in
            self?.queue.async { [weak self] in
                guard let self, let event = try? JSONDecoder().decode(AIActivityEvent.self, from: data) else { return }
                self.store.apply(event)
            }
        }
        do { try candidate.start(); listener = candidate; bridgeMessage = nil }
        catch { bridgeMessage = error.localizedDescription }
    }
}
