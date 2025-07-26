//
//  FullscreenMediaDetection.swift
//  boringNotch
//
//  Created by Richard Kunkli on 06/09/2024.
//

import Defaults
import MacroVisionKit
import SwiftUI

@MainActor
class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    private let detector: MacroVisionKit
    @ObservedObject private var musicManager = MusicManager.shared

    @Published private(set) var fullscreenStatus: [String: Bool] = [:]

    private init() {
        self.detector = MacroVisionKit.shared
        detector.configuration.includeSystemApps = true
        setupNotificationObservers()
        updateFullScreenStatus()
    }

    private func setupNotificationObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleChange),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleChange),
                       name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func handleChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateFullScreenStatus()
        }
    }

    private func updateFullScreenStatus() {
        guard Defaults[.enableFullscreenMediaDetection] else {
            let reset = Dictionary(uniqueKeysWithValues: NSScreen.screens.map { ($0.localizedName, false) })
            if reset != fullscreenStatus {
                fullscreenStatus = reset
            }
            return
        }
        

        let apps = detector.detectFullscreenApps(debug: false)
        let names = NSScreen.screens.map { $0.localizedName }
        var newStatus: [String: Bool] = [:]
        for name in names {
            newStatus[name] = apps.contains { $0.screen.localizedName == name && $0.bundleIdentifier != "com.apple.finder" && ($0.bundleIdentifier == musicManager.bundleIdentifier || Defaults[.hideNotchOption] == .always) }
        }

        if newStatus != fullscreenStatus {
            fullscreenStatus = newStatus
            NSLog("✅ Fullscreen status: \(newStatus)")
        }
    }

    private func cleanupNotificationObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
