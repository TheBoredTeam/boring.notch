//
//  GitHubHUDManager.swift
//  boringNotch
//
//  Observable state + refresh policy for the GitHub HUD. Refreshes only while
//  the HUD is visible, no more often than the user's interval, and backs off
//  when offline or rate-limited.
//

import Defaults
import Foundation
import Network
import SwiftUI

@MainActor
final class GitHubHUDManager: ObservableObject {
    static let shared = GitHubHUDManager()

    enum LoadState: Equatable {
        case signedOut
        case loading
        case loaded
        case offline
        case rateLimited(Date?)
        case authFailed
        case failed(String)
    }

    @Published private(set) var state: LoadState = .signedOut
    @Published private(set) var snapshot: GitHubSnapshot?

    private let monitor = NWPathMonitor()
    private var isOnline = true
    private var refreshTask: Task<Void, Never>?
    private var visibleCount = 0
    private var lastAttempt: Date?
    private var inFlight = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied
                if wasOffline && self.isOnline && self.visibleCount > 0 { self.refresh(force: true) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "boringNotch.github.network", qos: .utility))
    }

    private var wantedSections: GitHubSections {
        var s: GitHubSections = []
        if Defaults[.githubShowNotifications] { s.insert(.notifications) }
        if Defaults[.githubShowPullRequests] { s.insert(.pullRequests) }
        if Defaults[.githubShowReviewRequests] { s.insert(.reviewRequests) }
        if Defaults[.githubShowIssues] { s.insert(.issues) }
        if Defaults[.githubShowActivity] { s.insert(.activity) }
        if Defaults[.githubShowActions] { s.insert(.actions) }
        if Defaults[.githubShowContributions] { s.insert(.contributions) }
        return s
    }

    private var refreshInterval: TimeInterval { TimeInterval(max(1, Defaults[.githubRefreshMinutes])) * 60 }

    // MARK: - Lifecycle

    func start() {
        visibleCount += 1
        guard visibleCount == 1 else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh(force: false)
                try? await Task.sleep(for: .seconds(30))   // cheap staleness check; network only when due
            }
        }
    }

    func stop() {
        visibleCount = max(0, visibleCount - 1)
        guard visibleCount == 0 else { return }
        refreshTask?.cancel(); refreshTask = nil
    }

    /// Called from settings after the token changes.
    func credentialsChanged() async {
        await GitHubAPIService.shared.clearCache()
        snapshot = nil
        lastAttempt = nil
        if GitHubAuthService.hasToken { refresh(force: true) } else { state = .signedOut }
    }

    // MARK: - Refresh

    func refresh(force: Bool) {
        guard GitHubAuthService.hasToken else { state = .signedOut; snapshot = nil; return }
        guard !inFlight else { return }
        if !isOnline { if snapshot == nil || state != .loaded { state = .offline }; return }

        if !force {
            if let until = rateLimitedUntil, until > Date() { return }
            if let last = lastAttempt, Date().timeIntervalSince(last) < refreshInterval { return }
        }
        let sections = wantedSections
        guard !sections.isEmpty else { state = .loaded; return }

        inFlight = true
        lastAttempt = Date()
        if snapshot == nil { state = .loading }

        Task {
            defer { inFlight = false }
            do {
                snapshot = try await GitHubAPIService.shared.fetchSnapshot(wants: sections)
                state = .loaded
            } catch GitHubAPIError.notAuthenticated {
                state = .signedOut
            } catch GitHubAPIError.unauthorized {
                state = .authFailed
            } catch GitHubAPIError.rateLimited(let reset) {
                rateLimitedUntil = reset
                state = .rateLimited(reset)
            } catch GitHubAPIError.offline {
                state = .offline
            } catch GitHubAPIError.forbidden {
                state = .failed("GitHub denied the request. Check the token's permissions.")
            } catch {
                state = snapshot == nil ? .failed("GitHub is unavailable right now.") : .loaded
            }
        }
    }

    private var rateLimitedUntil: Date?
}
