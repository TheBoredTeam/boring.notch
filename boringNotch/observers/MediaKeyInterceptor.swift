//
//  MediaKeyInterceptor.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-23.

import Foundation
import AppKit
import ApplicationServices
import Defaults
import AVFoundation

private let kSystemDefinedEventType = CGEventType(rawValue: 14)!

enum MediaKeyKind: Int {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case keyboardBrightnessUp = 21
    case keyboardBrightnessDown = 22
}

struct MediaKeyModifiers: OptionSet, Equatable {
    let rawValue: Int
    static let option = Self(rawValue: 1 << 0)
    static let shift = Self(rawValue: 1 << 1)
    static let command = Self(rawValue: 1 << 2)
}

enum MediaKeyDisposition: Equatable {
    case handle
    case passThrough
}

struct MediaKeyPolicy {
    static func disposition(
        for key: MediaKeyKind, modifiers: MediaKeyModifiers,
        replacementEnabled: Bool, selectedSource: OSDControlSource,
        volumeSupported: Bool, brightnessSupported: Bool, backlightSupported: Bool
    ) -> MediaKeyDisposition {
        guard replacementEnabled else { return .passThrough }
        if modifiers.contains(.command) {
            switch key {
            case .soundUp, .soundDown, .mute:
                return .passThrough
            case .brightnessUp, .brightnessDown:
                return backlightSupported ? .handle : .passThrough
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                break
            }
        }
        switch key {
        case .soundUp, .soundDown, .mute:
            return selectedSource == .builtin && volumeSupported ? .handle : .passThrough
        case .brightnessUp, .brightnessDown:
            return selectedSource == .builtin && brightnessSupported ? .handle : .passThrough
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            return backlightSupported ? .handle : .passThrough
        }
    }

    static func stepDivisor(modifiers: MediaKeyModifiers) -> Float {
        modifiers.contains([.option, .shift]) ? 4 : 1
    }

    static func shouldPlayVolumeFeedback(
        preferenceEnabled: Bool, modifiers: MediaKeyModifiers
    ) -> Bool {
        preferenceEnabled != modifiers.contains(.shift)
    }
}

struct MediaKeyTapLifecycle: Equatable {
    private(set) var generation: UInt64 = 0
    private(set) var desiredEnabled = false

    mutating func beginStart() -> UInt64 {
        generation &+= 1
        desiredEnabled = true
        return generation
    }

    mutating func stop() {
        generation &+= 1
        desiredEnabled = false
    }

    func acceptsCompletion(generation: UInt64) -> Bool {
        desiredEnabled && self.generation == generation
    }
}

final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let step: Float = 1.0 / 16.0
    private var audioPlayer: AVAudioPlayer?
    private var lifecycle = MediaKeyTapLifecycle()
    private var screenObservers: [any NSObjectProtocol] = []
    
    private init() {
        let center = DistributedNotificationCenter.default()
        screenObservers.append(center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        })
        screenObservers.append(center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard self != nil else { return }
                BoringViewCoordinator.shared.applyOSDSources()
            }
        })
    }

    private var isTapActive: Bool {
        eventTap != nil && runLoopSource != nil
    }

    // MARK: - Accessibility (via XPC)

    @MainActor func requestAccessibilityAuthorization() {
        XPCHelperClient.shared.requestAccessibilityAuthorization()
    }

    @MainActor func ensureAccessibilityAuthorization(promptIfNeeded: Bool = false) async -> Bool {
        await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: promptIfNeeded)
    }

    // MARK: - Event Tap
    
    @MainActor func start(promptIfNeeded: Bool = false) async {
        let startGeneration = lifecycle.beginStart()
        // Ensure OSD replacement is enabled
        guard Defaults[.osdReplacement] else {
            stop()
            return
        }

        // Only require Accessibility if any selected source uses the built-in controls
        let needsAccessibility = Defaults[.osdBrightnessSource] == .builtin || Defaults[.osdVolumeSource] == .builtin
        if needsAccessibility {
            let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
            if !authorized {
                if promptIfNeeded {
                    let granted = await ensureAccessibilityAuthorization(promptIfNeeded: true)
                    guard granted else { return }
                } else {
                    return
                }
            }
        }

        guard lifecycle.acceptsCompletion(generation: startGeneration),
              Defaults[.osdReplacement]
        else { return }

        if let eventTap, isTapActive {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return
        }

        if eventTap != nil || runLoopSource != nil {
            tearDownTap()
        }

        let mask = CGEventMask(1 << kSystemDefinedEventType.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

                return MainActor.assumeIsolated {
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        interceptor.reenableEventTap(after: type)
                        return nil
                    }
                    return interceptor.handleEvent(cgEvent)
                }
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        if let eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
        } else {
            Log.osd.error("⚠️ [MediaKeyInterceptor] Failed to create media-key event tap")
        }
    }

    @MainActor func stop() {
        lifecycle.stop()
        tearDownTap()
    }

    @MainActor private func tearDownTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
    }

    @MainActor private func reenableEventTap(after type: CGEventType) {
        guard lifecycle.desiredEnabled, Defaults[.osdReplacement] else { return }
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)

        let reason: String
        switch type {
        case .tapDisabledByTimeout:
            reason = "timeout"
        case .tapDisabledByUserInput:
            reason = "user input"
        default:
            reason = "unknown reason"
        }

        Log.osd.debug("ℹ️ [MediaKeyInterceptor] Re-enabled media-key event tap after \(reason)")
    }

    // MARK: - Event Handling

    @MainActor private func handleEvent(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        // Ensure the CGEvent has a valid type before converting to NSEvent
        guard cgEvent.type != .null else {
            return Unmanaged.passUnretained(cgEvent)
        }

        guard let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(cgEvent)
        }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let stateByte = ((data1 & 0xFF00) >> 8)

        // 0xA = key down, 0xB = key up. Only handle key down.
        guard stateByte == 0xA,
              let keyType = MediaKeyKind(rawValue: keyCode) else {
            return Unmanaged.passUnretained(cgEvent)
        }

        // Determine which source is selected for this control (brightness/volume/keyboard)
        let selectedSource: OSDControlSource = {
            switch keyType {
            case .soundUp, .soundDown, .mute:
                return Defaults[.osdVolumeSource]
            case .brightnessUp, .brightnessDown:
                return Defaults[.osdBrightnessSource]
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                return .builtin
            }
        }()

        let flags = nsEvent.modifierFlags
        var modifiers: MediaKeyModifiers = []
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        let volumeSupported = keyType == .mute
            ? VolumeManager.shared.canToggleMute || VolumeManager.shared.canAdjustVolume
            : VolumeManager.shared.canAdjustVolume
        guard MediaKeyPolicy.disposition(
            for: keyType, modifiers: modifiers,
            replacementEnabled: Defaults[.osdReplacement], selectedSource: selectedSource,
            volumeSupported: volumeSupported,
            brightnessSupported: BrightnessManager.shared.canAdjustBrightness,
            backlightSupported: KeyboardBacklightManager.shared.canAdjustBrightness) == .handle
        else { return Unmanaged.passUnretained(cgEvent) }

        let option = modifiers.contains(.option)
        let shift = modifiers.contains(.shift)
        let command = modifiers.contains(.command)

        // Handle option key action (without shift)
        if option && !shift {
            if handleOptionAction(for: keyType, command: command) {
                return nil
            }
        }

        // Handle normal key press
        handleKeyPress(keyType: keyType, modifiers: modifiers)
        return nil
    }

    @MainActor private func handleOptionAction(for keyType: MediaKeyKind, command: Bool) -> Bool {
        let action = Defaults[.optionKeyAction]

        switch action {
        case .openSettings:
            openSystemSettings(for: keyType, command: command)
            return true
        case .showOSD:
            showOSD(for: keyType, command: command)
            return true
        case .none:
            return true
        }
    }

    private func prepareAudioPlayerIfNeeded() {
        guard audioPlayer == nil else { return }

        let defaultPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        if FileManager.default.fileExists(atPath: defaultPath) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: defaultPath))
                Log.osd.debug("🔊 [MediaKeyInterceptor] Loaded default Bezel audio from: \(defaultPath)")
            } catch {
                Log.osd.error("⚠️ [MediaKeyInterceptor] Failed to init AVAudioPlayer with default path \(defaultPath): \(error.localizedDescription)")
            }
        } else {
            Log.osd.error("⚠️ [MediaKeyInterceptor] Default bezel audio not found at: \(defaultPath)")
        }

        if let player = audioPlayer {
            player.volume = 1.0
            player.numberOfLoops = 0
            player.prepareToPlay()
        }
    }

    private func playFeedbackSound(modifiers: MediaKeyModifiers) {
        // Single-key lookup — persistentDomain(forName:) materialized the
        // entire NSGlobalDomain on every volume key press.
        let feedback = CFPreferencesCopyAppValue(
            "com.apple.sound.beep.feedback" as CFString,
            kCFPreferencesAnyApplication
        ) as? Int
        guard MediaKeyPolicy.shouldPlayVolumeFeedback(
            preferenceEnabled: feedback == 1, modifiers: modifiers)
        else { return }

        prepareAudioPlayerIfNeeded()
        guard let player = audioPlayer else {
            Log.osd.error("⚠️ [MediaKeyInterceptor] No audio player available to play feedback sound")
            return
        }
        if let url = player.url {
            Log.osd.debug("🔊 [MediaKeyInterceptor] Playing feedback sound from: \(url.path)")
        } else {
            Log.osd.debug("🔊 [MediaKeyInterceptor] Playing feedback sound (no url available for AVAudioPlayer)")
        }
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }

    @MainActor private func handleKeyPress(
        keyType: MediaKeyKind, modifiers: MediaKeyModifiers
    ) {
        let stepDivisor = MediaKeyPolicy.stepDivisor(modifiers: modifiers)
        let command = modifiers.contains(.command)

        switch keyType {
        case .soundUp:
            Task { @MainActor in
                self.playFeedbackSound(modifiers: modifiers)
                VolumeManager.shared.increase(stepDivisor: stepDivisor)
            }
        case .soundDown:
            Task { @MainActor in
                self.playFeedbackSound(modifiers: modifiers)
                VolumeManager.shared.decrease(stepDivisor: stepDivisor)
            }
        case .mute:
            Task { @MainActor in
                VolumeManager.shared.toggleMuteAction()
            }
        case .brightnessUp, .keyboardBrightnessUp:
            let delta = step / stepDivisor
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessUp || command)
        case .brightnessDown, .keyboardBrightnessDown:
            let delta = -(step / stepDivisor)
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessDown || command)
        }
    }

    private func adjustBrightness(delta: Float, keyboard: Bool) {
        Task { @MainActor in
            if keyboard {
                KeyboardBacklightManager.shared.setRelative(delta: delta)
            } else {
                BrightnessManager.shared.setRelative(delta: delta)
            }
        }
    }

    private func showOSD(for keyType: MediaKeyKind, command: Bool) {
        Task { @MainActor in
            switch keyType {
            case .soundUp, .soundDown, .mute:
                let v = VolumeManager.shared.rawVolume
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(v))
            case .brightnessUp, .brightnessDown:
                if command {
                    let v = KeyboardBacklightManager.shared.rawBrightness
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
                } else {
                    let v = BrightnessManager.shared.rawBrightness
                    let target = await BrightnessManager.shared.brightnessTargetUUID()
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(v), targetScreenUUID: target)
                }
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                let v = KeyboardBacklightManager.shared.rawBrightness
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
            }
        }
    }

    private func openSystemSettings(for keyType: MediaKeyKind, command: Bool) {
        let urlString: String

        switch keyType {
        case .soundUp, .soundDown, .mute:
            urlString = "x-apple.systempreferences:com.apple.preference.sound"
        case .brightnessUp, .brightnessDown:
            if command {
                urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
            } else {
                urlString = "x-apple.systempreferences:com.apple.preference.displays"
            }
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
        }

        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
