//
//  KairoVoiceTrigger.swift
//  Kairo — Caps Lock voice trigger (like Claude app)
//
//  Double-tap Fn key to activate Kairo voice.
//  The notch breathes cyan, all audio pauses,
//  Kairo listens. Tap Fn again or press Esc to stop.
//

import AppKit
import AVFoundation
import Combine
import SwiftUI

class KairoVoiceTrigger: ObservableObject {
    static let shared = KairoVoiceTrigger()

    @Published var isActive = false

    private var flagsMonitor: Any?
    private var lastFnTime: Date = .distantPast
    private let doubleTapWindow: TimeInterval = 0.4

    func start() {
        // Monitor all key flag changes globally (catches Fn, Caps Lock, etc.)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
        }

        // Also monitor locally (when Kairo is focused)
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }

        // Escape key to cancel
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 && self?.isActive == true { // Esc
                DispatchQueue.main.async { self?.deactivate() }
            }
        }

        print("[KairoVoice] Trigger ready — double-tap Fn to activate")
    }

    private func handleFlags(_ event: NSEvent) {
        // Detect Fn key (keyCode 63) press
        if event.keyCode == 63 {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastFnTime)

            if elapsed < doubleTapWindow && !isActive {
                // Double-tap detected → activate
                DispatchQueue.main.async { self.activate() }
            } else if isActive {
                // Already active, Fn pressed again → deactivate
                DispatchQueue.main.async { self.deactivate() }
            }

            lastFnTime = now
        }
    }

    func activate() {
        guard !isActive else { return }
        isActive = true

        // Pause all system audio
        pauseAllAudio()

        // Haptic
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)

        // Tell the notch
        NotificationCenter.default.post(name: .kairoVoiceActivated, object: nil)

        // Start listening
        KairoVoiceEngine.shared.startListening()

        print("[KairoVoice] Activated — listening")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        // Stop listening
        KairoVoiceEngine.shared.stopListening()

        // Tell the notch
        NotificationCenter.default.post(name: .kairoVoiceDismissed, object: nil)

        // Resume audio after response
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.resumeAllAudio()
        }

        print("[KairoVoice] Deactivated")
    }

    // MARK: - Audio Control

    private func pauseAllAudio() {
        // Send media pause command via MediaRemote
        if let bundle = CFBundleCreate(kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
           let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            let sendCommand = unsafeBitCast(ptr, to: (@convention(c) (Int, AnyObject?) -> Void).self)
            sendCommand(1, nil) // 1 = Pause
        }
    }

    private func resumeAllAudio() {
        // Only resume if music was playing before
        guard MusicManager.shared.isPlaying == false else { return }
        if let bundle = CFBundleCreate(kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
           let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            let sendCommand = unsafeBitCast(ptr, to: (@convention(c) (Int, AnyObject?) -> Void).self)
            sendCommand(0, nil) // 0 = Play
        }
    }

    deinit {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
