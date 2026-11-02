import AppKit
import Combine
import SwiftUI

@MainActor
final class AIActivityManager: ObservableObject {
    static let shared = AIActivityManager()
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "aiActivities.enabled")
            if isEnabled { start() } else { stop() }
        }
    }
    @Published var observesDesktop: Bool {
        didSet { UserDefaults.standard.set(observesDesktop, forKey: "aiActivities.observeDesktop") }
    }
    @Published private(set) var snapshot = AIActivitySnapshot()
    /// Companions shown in the closed notch, one per provider, most urgent first.
    @Published private(set) var notchGroups: [AIActivityGroup] = []
    /// The waiting session whose question drops down under the closed notch.
    @Published private(set) var attentionBanner: AIActivitySession?
    @Published private(set) var previewSession: AIActivitySession?
    @Published private(set) var previewCompanion: AIActivitySession?
    @Published private(set) var allowsAnimation = true
    @Published private(set) var connectionMessage: String?
    @Published private(set) var setupMessage: String?
    @Published private(set) var isConfiguring = false

    private var pollingTask: Task<Void, Never>?
    private var previewDeadline: Date?
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    private init() {
        UserDefaults.standard.register(defaults: ["aiActivities.enabled": true, "aiActivities.observeDesktop": false])
        isEnabled = UserDefaults.standard.bool(forKey: "aiActivities.enabled")
        observesDesktop = UserDefaults.standard.bool(forKey: "aiActivities.observeDesktop")
    }

    /// The session the lamps describe.
    var selectedSession: AIActivitySession? { notchGroups.first?.lead }

    var sessions: [AIActivitySession] {
        let entries = snapshot.sessions + [previewSession, previewCompanion].compactMap { $0 }
        return entries.sorted {
            if $0.status.priority != $1.status.priority { return $0.status.priority > $1.status.priority }
            return $0.updatedAt > $1.updatedAt
        }
    }

    /// Problems that silently stop events from reaching this notch, shown in the AI tab.
    var connectionWarnings: [String] {
        var warnings: [String] = []
        if let message = connectionMessage { warnings.append(message) }
        for provider in [AIProvider.claudeCode, .codex]
        where snapshot.hookConnections[provider.rawValue]?.state == .needsReconnect {
            warnings.append("\(provider.name) hooks run another copy of Boring Notch. Reconnect in Settings → AI Activities.")
        }
        return warnings
    }

    func start() {
        guard isEnabled, pollingTask == nil else { return }
        installVisibilityObservers()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                do { try await Task.sleep(for: .seconds(self.allowsAnimation ? 1 : 5)) } catch { return }
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        withAnimation(.smooth) { notchGroups = []; attentionBanner = nil }
        previewSession = nil
        previewCompanion = nil
        previewDeadline = nil
        snapshot = AIActivitySnapshot(hookConnections: snapshot.hookConnections)
        if !isEnabled && BoringViewCoordinator.shared.currentView == .ai {
            BoringViewCoordinator.shared.currentView = .home
        }
        Task { await XPCHelperClient.shared.stopAIActivityMonitoring() }
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
        for observer in distributedObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        distributedObservers = []
    }

    func refresh() async {
        guard isEnabled, allowsAnimation else { return }
        do {
            let updated = try await XPCHelperClient.shared.aiActivitySnapshot(
                observeDesktop: observesDesktop && allowsAnimation,
                frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            guard isEnabled, !Task.isCancelled else { return }
            if updated.sessions != snapshot.sessions || updated.hookConnections != snapshot.hookConnections
                || updated.accessibilityAuthorized != snapshot.accessibilityAuthorized
                || updated.bridgeReady != snapshot.bridgeReady || updated.message != snapshot.message
                || updated.desktopObservationEnabled != snapshot.desktopObservationEnabled {
                snapshot = updated
            }
            connectionMessage = updated.message
        } catch {
            guard isEnabled, !Task.isCancelled else { return }
            snapshot = AIActivitySnapshot()
            connectionMessage = "AI event bridge disconnected. Reconnecting…"
        }
        if let deadline = previewDeadline, deadline <= Date() { clearPreview() }
        selectSession()
    }

    func configureHooks(_ provider: AIProvider, remove: Bool) async {
        guard !isConfiguring else { return }
        isConfiguring = true
        defer { isConfiguring = false }
        do { setupMessage = try await XPCHelperClient.shared.configureAIActivityHooks(provider, remove: remove) }
        catch { setupMessage = "Could not update hooks: \(error.localizedDescription)" }
        await refresh()
        await refreshConnections()
    }

    func refreshConnections() async {
        if let status = try? await XPCHelperClient.shared.aiActivityHookStatus(), status != snapshot.hookConnections {
            snapshot.hookConnections = status
        }
    }

    func enableDesktopObservation() async {
        let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
        observesDesktop = granted
        if !granted { setupMessage = "Grant Accessibility access to BoringNotchXPCHelper in System Settings, then try again." }
        await refresh()
    }

    func preview(provider: AIProvider, status: AIActivityStatus, action: AIActivityAction? = nil,
                 withCompanion: Bool = false) {
        guard isEnabled else { return }
        var session = AIActivitySession(provider: provider, sessionID: "preview", status: status,
                                        source: .preview, project: "Preview", reason: "Preview only — no live agent event")
        if status == .working {
            session.action = action
            session.actionDetail = action == .reading || action == .editing ? "Preview.swift" : nil
        }
        if status == .completed { session.completedAt = Date() }
        previewSession = session
        // A second provider working alongside, to preview the stacked companions.
        previewCompanion = withCompanion ? {
            var companion = AIActivitySession(provider: provider == .codex ? .claudeCode : .codex,
                                              sessionID: "preview-companion", status: .working, source: .preview,
                                              project: "Preview", reason: "Preview only — no live agent event")
            companion.action = .running
            companion.actionDetail = "swift"
            return companion
        }() : nil
        previewDeadline = Date().addingTimeInterval(20)
        selectSession()
    }

    func clearPreview() { previewSession = nil; previewCompanion = nil; previewDeadline = nil; selectSession() }

    func dismiss(_ session: AIActivitySession) {
        if session.source == .preview { clearPreview(); return }
        Task {
            await XPCHelperClient.shared.dismissAIActivity(session.id)
            await refresh()
        }
    }

    func open(_ session: AIActivitySession) {
        if session.provider == .claudeCode, let hostID = session.hostSessionID,
           hostID.hasPrefix("local_"), (7...70).contains(hostID.count),
           hostID.dropFirst(6).allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
           let url = URL(string: "claude://code/continue?session=\(hostID)") {
            NSWorkspace.shared.open(url)
            return
        }
        var appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: session.provider.bundleIdentifier)
        // Newer ChatGPT desktop distributions can share the Codex app identity.
        if appURL == nil && session.provider == .chatgpt {
            appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AIProvider.codex.bundleIdentifier)
        }
        if let appURL { NSWorkspace.shared.openApplication(at: appURL, configuration: .init()) }
    }

    private func selectSession() {
        // A preview always shows, whatever its state; it replaces live companions while it lasts.
        let next = previewSession.map { preview in [AIActivityGroup(lead: preview)] + (previewCompanion.map { [AIActivityGroup(lead: $0)] } ?? []) }
            ?? AIActivitySession.grouped(snapshot.sessions, at: Date())
        let banner = next.first.map(\.lead).flatMap { $0.showsAttentionBanner(at: Date()) ? $0 : nil }
        guard next != notchGroups || banner != attentionBanner else { return }
        // Like the music activity, animate so the notch resizes instead of snapping shut.
        withAnimation(.smooth) {
            notchGroups = next
            attentionBanner = banner
        }
    }

    private func installVisibilityObservers() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        // Returning to an app acknowledges its finished sessions; refresh at once so a quick
        // glance between one-second polls still counts and the green light yields promptly.
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.allowsAnimation = false }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.allowsAnimation = true }
            })
        }
        for (name, visible) in [("com.apple.screenIsLocked", false), ("com.apple.screenIsUnlocked", true)] {
            distributedObservers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.allowsAnimation = visible }
                })
        }
    }
}
