//
//  MediaEnvironment.swift
//  boringNotch
//
//  Created as part of the architecture remediation.
//

import Foundation

/// Owns the launch-time MediaRemote (Now Playing) availability probe.
///
/// Split out of MusicManager so nothing needs to instantiate the whole
/// music stack just to learn the flag: `Defaults.Keys.mediaController`'s
/// default previously read `MusicManager.shared.isNowPlayingDeprecated`
/// while MusicManager itself reads that key — reading the key from inside
/// MusicManager's lazy init could re-enter its own initialization and trap.
/// The result is persisted so static Defaults defaults are meaningful even
/// before this launch's probe finishes.
@MainActor
final class MediaEnvironment: ObservableObject {
    static let shared = MediaEnvironment()

    @Published private(set) var isNowPlayingDeprecated: Bool

    private let checker = MediaChecker()
    private var resolveTask: Task<Void, Never>?

    static let persistenceKey = "MediaEnvironment.isNowPlayingDeprecated"

    private init() {
        isNowPlayingDeprecated = UserDefaults.standard.bool(forKey: Self.persistenceKey)
    }

    /// Probe once; concurrent calls coalesce behind the first.
    func resolve() {
        guard resolveTask == nil else { return }
        resolveTask = Task { @MainActor in
            defer { resolveTask = nil }
            let resolved = (try? await checker.checkDeprecationStatus()) ?? false
            if resolved != isNowPlayingDeprecated {
                isNowPlayingDeprecated = resolved
            }
            UserDefaults.standard.set(resolved, forKey: Self.persistenceKey)
        }
    }
}
