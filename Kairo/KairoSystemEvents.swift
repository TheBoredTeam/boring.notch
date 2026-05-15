//
//  KairoSystemEvents.swift
//  Kairo — System event interception layer
//
//  Catches volume/brightness/media key events and publishes
//  them as Kairo notifications. Kairo already handles
//  the actual interception via VolumeManager and BrightnessManager.
//  This adds Kairo-specific notification names and bridges events
//  to the notification engine for display.
//

import AppKit
import Combine
import CoreAudio
import SwiftUI

// ═══════════════════════════════════════════
// MARK: - Notification Names
// ═══════════════════════════════════════════

extension Notification.Name {
    static let kairoShowVolume = Notification.Name("kairoShowVolume")
    static let kairoHideVolume = Notification.Name("kairoHideVolume")
    static let kairoShowBrightness = Notification.Name("kairoShowBrightness")
    static let kairoHideBrightness = Notification.Name("kairoHideBrightness")
    static let kairoPlaybackChanged = Notification.Name("kairoPlaybackChanged")
    static let kairoTrackSkipped = Notification.Name("kairoTrackSkipped")
    static let kairoTrackChanged = Notification.Name("kairoTrackChanged")
}

// ═══════════════════════════════════════════
// MARK: - System Event Bridge
// ═══════════════════════════════════════════

class KairoSystemEventBridge: ObservableObject {
    static let shared = KairoSystemEventBridge()

    @Published var currentVolume: Float = 0.5
    @Published var isMuted: Bool = false
    @Published var currentBrightness: Float = 1.0
    @Published var showVolumeHUD: Bool = false
    @Published var showBrightnessHUD: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var volumeHideTimer: Timer?
    private var brightnessHideTimer: Timer?

    func start() {
        let vol = VolumeManager.shared
        let music = MusicManager.shared

        // Volume changes
        vol.$rawVolume.receive(on: RunLoop.main)
            .sink { [weak self] (v: Float) in
                self?.currentVolume = v; self?.showVolumeHUD = true; self?.scheduleVolumeHide()
            }.store(in: &cancellables)

        vol.$isMuted.receive(on: RunLoop.main)
            .sink { [weak self] (m: Bool) in
                self?.isMuted = m; self?.showVolumeHUD = true; self?.scheduleVolumeHide()
            }.store(in: &cancellables)

        // Music state
        music.$isPlaying.receive(on: RunLoop.main)
            .sink { (playing: Bool) in
                NotificationCenter.default.post(name: .kairoPlaybackChanged, object: nil, userInfo: ["isPlaying": playing])
            }.store(in: &cancellables)

        music.$songTitle.receive(on: RunLoop.main)
            .sink { (title: String) in
                guard !title.isEmpty, title != "Nothing Playing" else { return }
                NotificationCenter.default.post(name: .kairoTrackChanged, object: nil, userInfo: ["title": title])
            }.store(in: &cancellables)

        print("[KairoEvents] System event bridge started")
    }

    private func scheduleVolumeHide() {
        volumeHideTimer?.invalidate()
        volumeHideTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { withAnimation(.spring(response: 0.65, dampingFraction: 0.78)) { self?.showVolumeHUD = false } }
        }
    }

    private func scheduleBrightnessHide() {
        brightnessHideTimer?.invalidate()
        brightnessHideTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { withAnimation(.spring(response: 0.65, dampingFraction: 0.78)) { self?.showBrightnessHUD = false } }
        }
    }
}
