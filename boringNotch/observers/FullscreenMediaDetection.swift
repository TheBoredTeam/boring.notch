// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Combine
import Defaults
import MacroVisionKit

/// Policy over the latest native fullscreen Space snapshot. A missing media
/// source does not mean that every fullscreen app is the Now Playing app.
enum FullscreenVisibilityPolicy {
    static func status(
        spaces: [(screenUUID: String?, runningApps: [String])],
        option: HideNotchOption,
        mediaSource: String?
    ) -> [String: Bool] {
        var status: [String: Bool] = [:]
        for space in spaces {
            guard let uuid = space.screenUUID else { continue }
            let hide: Bool
            switch option {
            case .never: hide = false
            case .always: hide = true
            case .nowPlayingOnly:
                hide = mediaSource.map { !$0.isEmpty && space.runningApps.contains($0) } ?? false
            }
            status[uuid] = (status[uuid] ?? false) || hide
        }
        return status
    }
}

@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()

    @Published private(set) var fullscreenStatus: [String: Bool] = [:]
    private var latestSpaces: [MacroVisionKit.FullScreenMonitor.SpaceInfo] = []
    private var monitorTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        monitorTask = Task { @MainActor [weak self] in
            // Subscribe after initialization, avoiding singleton initialization
            // recursion through MusicManager and the view coordinator.
            self?.observePolicy()
            let stream = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in stream {
                guard let self else { return }
                latestSpaces = spaces
                updateStatus(option: Defaults[.hideNotchOption], mediaSource: MusicManager.shared.bundleIdentifier)
            }
        }
    }

    deinit { monitorTask?.cancel() }

    private func observePolicy() {
        Publishers.CombineLatest(
            Defaults.publisher(.hideNotchOption).map(\.newValue).removeDuplicates(),
            MusicManager.shared.$bundleIdentifier.removeDuplicates()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] option, mediaSource in
            // Use the published source value: @Published emits before storing it.
            self?.updateStatus(option: option, mediaSource: mediaSource)
        }
        .store(in: &cancellables)
    }

    private func updateStatus(option: HideNotchOption, mediaSource: String?) {
        fullscreenStatus = FullscreenVisibilityPolicy.status(
            spaces: latestSpaces.map { ($0.screenUUID, $0.runningApps) },
            option: option,
            mediaSource: mediaSource
        )
    }
}
