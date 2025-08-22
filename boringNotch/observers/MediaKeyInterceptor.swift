//
//  MediaKeyInterceptor.swift
//  boringNotch
//
//  Created by JeanLouis on 21/08/2025.

import Foundation
import AppKit
import os.log

private let kSystemDefinedEventType = CGEventType(rawValue: 14)!

final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()

    private var eventTap: CFMachPort? = nil
    private var runLoopSource: CFRunLoopSource? = nil
    private let brightnessStep: Float = 1.0 / 16.0

    private init() {}

    func start() {
        guard eventTap == nil else { return }
        let isAXTrusted = AXIsProcessTrusted()
        if (!isAXTrusted ){
            let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
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


    private func handleSystemDefined(event cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nsEvent = NSEvent(cgEvent: cgEvent), nsEvent.type == .systemDefined, nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(cgEvent)
        }
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = (data1 & 0x0000_FFFF)
    let stateByte = (keyFlags & 0xFF00) >> 8
    // 0xA = key down, 0xB = key up for media (systemDefined subtype 8) events.
    // We only want to act on the key down to avoid double-trigger (press + release).
    let isPress = (stateByte == 0xA)
    let isRepeat = (stateByte == 0xB)
    guard (isPress || isRepeat) else { return Unmanaged.passRetained(cgEvent) }

        enum NXKeyType: Int { case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7 }
      

        guard let nx = NXKeyType(rawValue: keyCode) else {
            return Unmanaged.passRetained(cgEvent)
        }
// Return nil to avoid apple native animation 
        switch nx {
        case .soundUp:
            VolumeManager.shared.increase()
            return nil
        case .soundDown:
            VolumeManager.shared.decrease()
            return nil
        case .mute:
            if isPress { VolumeManager.shared.toggleMuteAction() }
            return nil
        case .brightnessUp:
            BrightnessManager.shared.setRelative(delta: brightnessStep)
            return nil
        case .brightnessDown:
            BrightnessManager.shared.setRelative(delta: -brightnessStep)
            return nil
        }
    }
}
