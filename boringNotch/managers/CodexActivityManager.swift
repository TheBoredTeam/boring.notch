//
//  CodexActivityManager.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation

/// Reads aggregate task state; presentation policy belongs to the views.
@MainActor
final class CodexActivityManager: ObservableObject {
    static let shared = CodexActivityManager()

    @Published private(set) var phase: CodexActivityPhase = .offline {
        didSet {
            if phase != oldValue { Log.codex.debug("Activity phase: \(self.phase.rawValue, privacy: .public)") }
        }
    }
    @Published private(set) var activeCount = 0
    var level: CodexActivityLevel { CodexActivityLevel(activeCount: activeCount) }
    var isActive: Bool { phase.isInProgress }
    var statusText: String { phase.statusText }

    private var monitoringTask: Task<Void, Never>?
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: CodexLoopbackSessionDelegate(), delegateQueue: nil)
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        apply(nil)
    }

    func apply(_ snapshot: CodexActivitySnapshot?, at now: Date = Date()) {
        let nextPhase = snapshot?.validatedPhase(at: now) ?? .offline
        let nextCount = snapshot?.validatedActiveCount(at: now) ?? 0
        if activeCount != nextCount { activeCount = nextCount }
        if phase != nextPhase { phase = nextPhase }
    }

    private func refresh() async {
        guard let endpoint = URL(string: "http://127.0.0.1:48731/activity") else { return }
        do {
            let (data, response) = try await session.data(from: endpoint)
            guard !Task.isCancelled else { return }
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200, data.count <= 4096 else {
                apply(nil)
                return
            }
            apply(try JSONDecoder().decode(CodexActivitySnapshot.self, from: data))
        } catch {
            guard !Task.isCancelled else { return }
            // A disconnected bird stays still instead of pretending to be busy.
            apply(nil)
        }
    }
}

private final class CodexLoopbackSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // The activity endpoint must remain on loopback, even if another process occupies its port.
        completionHandler(nil)
    }
}
