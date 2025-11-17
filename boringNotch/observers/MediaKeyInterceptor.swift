//
//  MediaKeyInterceptor.swift
//  boringNotch
//
//  Created by JeanLouis on 21/08/2025.

import Foundation
import AppKit
import os.log
import ApplicationServices
import IOKit
import Defaults

private let kSystemDefinedEventType = CGEventType(rawValue: 14)!

final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()

    private enum NXKeyType: Int { case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7 }

    private var eventTap: CFMachPort? = nil
    private var runLoopSource: CFRunLoopSource? = nil
    private let volumeStep: Float = 1.0 / 16.0
    private let brightnessStep: Float = 1.0 / 16.0

    private init() {}

    func isAccessibilityAuthorized() -> Bool {
        return AXIsProcessTrusted()
    }

    func start(requireAccessibility: Bool = true, promptIfNeeded: Bool = false) {
        guard eventTap == nil else { return }

        if requireAccessibility && !isAccessibilityAuthorized() {
            if promptIfNeeded {
                Task { @MainActor in
                    let granted = await self.ensureAccessibilityAuthorization(promptIfNeeded: true)
                    if granted {
                        // Start again but don't prompt now
                        self.start(requireAccessibility: false, promptIfNeeded: false)
                    }
                }
            }
            return
        }

        let mask = (1 << kSystemDefinedEventType.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                return interceptor.handleSystemDefined(event: cgEvent)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        if let eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource { CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil
        eventTap = nil
    }

      func requestAccessibilityAuthorization() {
          XPCHelperClient.shared.requestAccessibilityAuthorization()
    }

    func ensureAccessibilityAuthorization(promptIfNeeded: Bool = false) async -> Bool {
        await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: promptIfNeeded)
    }


    @MainActor private func handleSystemDefined(event cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nsEvent = NSEvent(cgEvent: cgEvent), nsEvent.type == .systemDefined, nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(cgEvent)
        }
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = (data1 & 0x0000_FFFF)
        let stateByte = (keyFlags & 0xFF00) >> 8
        // 0xA = key down, 0xB = key up for media (systemDefined subtype 8) events.
        // Only handle the key-down event to avoid duplicate handling.
        let isKeyDown = (stateByte == 0xA)

        guard isKeyDown else { return Unmanaged.passRetained(cgEvent) }
        guard let nx = NXKeyType(rawValue: keyCode) else {
                return Unmanaged.passRetained(cgEvent)
            }
        // Inspect modifier flags to support option/shift/command behaviors
        let flags = nsEvent.modifierFlags
        let optionDown = flags.contains(.option)
        let shiftDown = flags.contains(.shift)
        let commandDown = flags.contains(.command)

        // Read configured action for Option alone presses
        let optionAction = Defaults[.optionKeyAction]

        // Determine step multiplier: Option+Shift -> quarter step (1/64)
        let stepDivisor: Float = (optionDown && shiftDown) ? 4.0 : 1.0

        switch nx {
        case .soundUp:
            // Option + media: either show settings, show HUD only, or do nothing
            if optionDown && !shiftDown {
                switch optionAction {
                case .openSettings:
                    openSystemSettings(for: nx)
                    return nil
                case .showHUD:
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(VolumeManager.shared.rawVolume))
                    return nil
                case .none:
                    return nil
                }
            }

            // Use the high-level API which also shows the HUD immediately with the target value
            VolumeManager.shared.increase(stepDivisor: stepDivisor)
            return nil
        case .soundDown:
            if optionDown && !shiftDown {
                switch optionAction {
                case .openSettings:
                    openSystemSettings(for: nx)
                    return nil
                case .showHUD:
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(VolumeManager.shared.rawVolume))
                    return nil
                case .none:
                    return nil
                }
            }

            VolumeManager.shared.decrease(stepDivisor: stepDivisor)
            return nil
        case .mute:
            if optionDown && !shiftDown {
                switch optionAction {
                case .openSettings:
                    openSystemSettings(for: nx)
                    return nil
                case .showHUD:
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(VolumeManager.shared.rawVolume))
                    return nil
                case .none:
                    return nil
            }
        }

            VolumeManager.shared.toggleMuteAction()
            return nil
        case .brightnessUp:
            if optionDown && !shiftDown {
                switch optionAction {
        case .openSettings:
                    openSystemSettings(for: nx)
                    return nil
        case .showHUD:
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(BrightnessManager.shared.rawBrightness))
                    return nil
        case .none:
                    return nil
        }
    }

            let delta = brightnessStep / stepDivisor
            if commandDown {
                KeyboardBacklightManager.shared.setRelative(delta: delta)
            } else {
                BrightnessManager.shared.setRelative(delta: delta)
            }
            return nil
        case .brightnessDown:
            if optionDown && !shiftDown {
                switch optionAction {
                case .openSettings:
                    openSystemSettings(for: nx)
                    return nil
                case .showHUD:
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(BrightnessManager.shared.rawBrightness))
                    return nil
                case .none:
                    return nil
                }
            }

            let delta = -(brightnessStep / stepDivisor)
            if commandDown {
                KeyboardBacklightManager.shared.setRelative(delta: delta)
            } else {
                BrightnessManager.shared.setRelative(delta: delta)
        }
            return nil
        }
    }

    private func openSystemSettings(for key: NXKeyType) {
        var urlString: String?
        switch key {
        case .soundUp, .soundDown, .mute:
            urlString = "x-apple.systempreferences:com.apple.preference.sound"
        case .brightnessUp, .brightnessDown:
            // Apple opens Displays for brightness keys
            urlString = "x-apple.systempreferences:com.apple.preference.displays"
        }

        guard let s = urlString, let url = URL(string: s) else { return }
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }
}
