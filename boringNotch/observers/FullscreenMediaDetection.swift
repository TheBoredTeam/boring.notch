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
    private var settingCancellable: AnyCancellable?
    
    private init() {
        settingCancellable = Defaults.publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                self?.setMonitoringEnabled(isEnabled)
            }
        setMonitoringEnabled(Defaults[.hideNotchOption] != .never)
    }
    
    deinit {
        monitorTask?.cancel()
        settingCancellable?.cancel()
    }

    private func setMonitoringEnabled(_ isEnabled: Bool) {
        if isEnabled {
            startMonitoring()
        } else {
            monitorTask?.cancel()
            monitorTask = nil
            if !fullscreenStatus.isEmpty {
                fullscreenStatus = [:]
            }
        }
    }

    private func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { @MainActor in
            let stream = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in stream {
                guard !Task.isCancelled else { break }
                updateStatus(with: spaces)
            }
        }
    }
    
    private func updateStatus(with spaces: [MacroVisionKit.FullScreenMonitor.SpaceInfo]) {
        var newStatus: [String: Bool] = [:]
        
        for space in spaces {
            if let uuid = space.screenUUID {
                let shouldDetect: Bool
                if Defaults[.hideNotchOption] == .nowPlayingOnly, let musicSourceBundle = MusicManager.shared.bundleIdentifier  {
                    shouldDetect = space.runningApps.contains(musicSourceBundle)
                } else {
                    shouldDetect = true
                }
                newStatus[uuid] = shouldDetect
            }
        }
        
        if fullscreenStatus != newStatus {
            fullscreenStatus = newStatus
        }
    }
}
