//
//  KairoVoiceTrigger.swift
//  Kairo — Voice trigger
//
//  Double-tap Fn to activate. Escape to stop.
//

import AppKit
import AVFoundation
import Carbon
import Combine
import SwiftUI

class KairoVoiceTrigger: ObservableObject {
    static let shared = KairoVoiceTrigger()

    @Published var isActive = false

    private var escapeMonitorGlobal: Any?
    private var escapeMonitorLocal: Any?
    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        print("[KairoVoice] Accessibility: \(trusted ? "granted" : "requesting...")")

        // F5 to activate, Escape to stop (global)
        escapeMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }

        // F5 / Escape (local, when Kairo is focused)
        escapeMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }

        print("[KairoVoice] Trigger ready — F5 to activate, Escape to stop")
    }

    private func handleKeyDown(_ event: NSEvent) {
        // F5 (keyCode 96) → toggle voice
        if event.keyCode == 96 {
            DispatchQueue.main.async {
                if self.isActive {
                    self.deactivate()
                } else {
                    self.activate()
                }
            }
        }

        // Escape → stop
        if event.keyCode == 53 && isActive {
            DispatchQueue.main.async { self.deactivate() }
        }
    }

    func activate() {
        guard !isActive else { return }
        isActive = true

        pauseAllAudio()

        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)

        NotificationCenter.default.post(name: .kairoVoiceActivated, object: nil)

        // Prefer the NEW Brain pipeline (ConversationLoop) if it's been
        // wired by AppDelegate. Falls back to the legacy KairoVoiceEngine
        // (Python backend on localhost:8420) when the new loop isn't ready.
        if let appDelegate = NSApp.delegate as? AppDelegate,
           let loop = appDelegate.conversationLoop {
            Task { @MainActor in loop.startTurn() }
            // Auto-clear active flag — ConversationLoop drives its own
            // presence lifecycle and will end on silence / max-listen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.isActive = false
            }
            print("[KairoVoice] Activated — routed to new Brain pipeline")
        } else {
            KairoVoiceEngine.shared.startListening()
            print("[KairoVoice] Activated — legacy backend (new loop not ready)")
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        KairoVoiceEngine.shared.stopListening()

        NotificationCenter.default.post(name: .kairoVoiceDismissed, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.resumeAllAudio()
        }

        print("[KairoVoice] Deactivated")
    }

    // MARK: - Audio Control

    private func pauseAllAudio() {
        if let bundle = CFBundleCreate(kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
           let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            let sendCommand = unsafeBitCast(ptr, to: (@convention(c) (Int, AnyObject?) -> Void).self)
            sendCommand(1, nil)
        }
    }

    private func resumeAllAudio() {
        guard MusicManager.shared.isPlaying == false else { return }
        if let bundle = CFBundleCreate(kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
           let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            let sendCommand = unsafeBitCast(ptr, to: (@convention(c) (Int, AnyObject?) -> Void).self)
            sendCommand(0, nil)
        }
    }

    deinit {
        [escapeMonitorGlobal, escapeMonitorLocal]
            .compactMap { $0 }.forEach { NSEvent.removeMonitor($0) }
    }
}
