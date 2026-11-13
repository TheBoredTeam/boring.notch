//
//  FullscreenMediaDetection.swift
//  boringNotch
//
//  Created by Richard Kunkli on 06/09/2024.
//

import Foundation
import Combine
import Defaults
import MacroVisionKit

@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()

    @Published var fullscreenStatus: [String: Bool] = [:]

    private var monitorTask: Task<Void, Never>?
    private var lastSpaces: [MacroVisionKit.FullScreenMonitor.SpaceInfo] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        startMonitoring()
        observeInputs()
    }

    deinit {
        monitorTask?.cancel()
    }

    private func startMonitoring() {
        monitorTask = Task { @MainActor in
            let stream = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in stream {
                lastSpaces = spaces
                updateStatus(with: spaces)
            }
        }
    }

    // The status also depends on the now-playing source and the hide option,
    // so recompute when either changes, not only on space changes.
    private func observeInputs() {
        let sourceChanged = MusicManager.shared.$bundleIdentifier
            .removeDuplicates()
            .map { _ in () }
        let optionChanged = Defaults.publisher(.hideNotchOption)
            .map { _ in () }

        sourceChanged.merge(with: optionChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.updateStatus(with: self.lastSpaces)
            }
            .store(in: &cancellables)
    }

    private func updateStatus(with spaces: [MacroVisionKit.FullScreenMonitor.SpaceInfo]) {
        var newStatus: [String: Bool] = [:]

        for space in spaces {
            if let uuid = space.screenUUID {
                let shouldDetect: Bool
                if Defaults[.hideNotchOption] == .nowPlayingOnly, let musicSourceBundle = MusicManager.shared.bundleIdentifier {
                    shouldDetect = space.runningApps.contains(musicSourceBundle)
                } else {
                    shouldDetect = true
                }
                newStatus[uuid] = shouldDetect
            }
        }

        self.fullscreenStatus = newStatus
    }
}
