//
//  DeveloperHUDManager.swift
//  boringNotch
//
//  Observable state for the Developer HUD. Sampling only runs while the HUD
//  is on screen (see `start()` / `stop()`), so an inactive HUD costs nothing.
//

import AppKit
import Defaults
import Foundation
import SwiftUI

@MainActor
final class DeveloperHUDManager: ObservableObject {
    static let shared = DeveloperHUDManager()

    enum GitState: Equatable {
        case idle
        case noProject
        case loading
        case notARepository
        case accessDenied
        case ready(GitSnapshot)
    }

    @Published private(set) var gitState: GitState = .idle
    @Published private(set) var metrics = SystemMetrics()
    @Published private(set) var environment = DevEnvironment()
    @Published private(set) var activeProjectIndex = 0

    private let gitService = GitService()
    private let metricsService = SystemMetricsService()
    private let detector = DevelopmentEnvironmentDetector()

    private var metricsTask: Task<Void, Never>?
    private var gitTask: Task<Void, Never>?
    private var environmentTask: Task<Void, Never>?
    private var visibleCount = 0

    private init() {}

    /// Display names of configured projects (folder names only).
    var projectNames: [String] {
        Defaults[.devHUDProjectBookmarks].map { Self.name(for: $0) }
    }

    // MARK: - Lifecycle

    func start() {
        visibleCount += 1
        guard visibleCount == 1 else { return }

        if Defaults[.devHUDShowGit] { gitState = Defaults[.devHUDProjectBookmarks].isEmpty ? .noProject : .loading }

        metricsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Defaults[.devHUDShowSystem] {
                    let service = self.metricsService
                    let sample = await Task.detached(priority: .utility) { service.sample() }.value
                    self.metrics = sample
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        gitTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Defaults[.devHUDShowGit] { await self.refreshGit() }
                try? await Task.sleep(for: .seconds(8))
            }
        }
        environmentTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wantsServers = Defaults[.devHUDShowServers]
                if wantsServers || Defaults[.devHUDShowBuild] || Defaults[.devHUDShowTasks] {
                    self.environment = await self.detector.detect(includeServers: wantsServers)
                }
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }

    func stop() {
        visibleCount = max(0, visibleCount - 1)
        guard visibleCount == 0 else { return }
        metricsTask?.cancel(); gitTask?.cancel(); environmentTask?.cancel()
        metricsTask = nil; gitTask = nil; environmentTask = nil
    }

    func selectProject(_ index: Int) {
        guard index != activeProjectIndex else { return }
        activeProjectIndex = index
        gitState = .loading
        Task { await refreshGit() }
    }

    // MARK: - Git

    private func refreshGit() async {
        let bookmarks = Defaults[.devHUDProjectBookmarks]
        guard !bookmarks.isEmpty else { gitState = .noProject; return }

        let index = resolveActiveIndex(bookmarks)
        if index != activeProjectIndex { activeProjectIndex = index }

        do {
            let snapshot = try await gitService.snapshot(forBookmark: bookmarks[index])
            gitState = .ready(snapshot)
        } catch GitServiceError.notARepository {
            gitState = .notARepository
        } catch {
            gitState = .accessDenied
        }
    }

    /// If an IDE window title mentions a configured project, prefer it (needs Accessibility).
    private func resolveActiveIndex(_ bookmarks: [Data]) -> Int {
        let current = min(activeProjectIndex, bookmarks.count - 1)
        guard bookmarks.count > 1 else { return current }
        let titles = DevelopmentEnvironmentDetector.ideWindowTitles()
        guard !titles.isEmpty else { return current }
        let names = bookmarks.map { Self.name(for: $0) }
        if titles.contains(where: { $0.localizedCaseInsensitiveContains(names[current]) }) { return current }
        if let match = names.firstIndex(where: { n in titles.contains { $0.localizedCaseInsensitiveContains(n) } }) {
            return match
        }
        return current
    }

    private static func name(for bookmark: Data) -> String {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return "Unavailable"
        }
        return url.lastPathComponent
    }

    // MARK: - Project management (used by settings)

    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func displayName(for bookmark: Data) -> String { name(for: bookmark) }
}
