//
//  LunarManager.swift
//  boringNotch
//
//  Created by Alexander on 2026-02-07.
//

import Foundation
import AppKit
import CoreGraphics
import SwiftUI

final class LunarManager: ObservableObject {
    static let shared = LunarManager()
    
    @Published private(set) var isLunarAvailable: Bool = false
    @Published private(set) var isListening: Bool = false
    
    private var eventListener: LunarEventListener?
    
    private init() {
        refreshAvailability()
    }
    
    // MARK: - Availability
    
    func refreshAvailability() {
        Task.detached { [weak self] in
            let available = await XPCHelperClient.shared.isLunarAvailable()
            await MainActor.run {
                self?.isLunarAvailable = available
            }
        }
    }
    
    // MARK: - Listening
    
    func startListening() {
        if isListening { return }

        let listener = eventListener ?? LunarEventListener(manager: self)
        eventListener = listener

        Task.detached { [weak self] in
            guard let self else { return }
            let started = await XPCHelperClient.shared.startLunarEventStream(listener: listener)
            await MainActor.run {
                self.isListening = started
                if !started {
                    self.isLunarAvailable = false
                }
            }
        }
    }
    
    func stopListening() {
        Task.detached { [weak self] in
            await XPCHelperClient.shared.stopLunarEventStream()
            await MainActor.run {
                self?.isListening = false
            }
        }
    }
    
    // MARK: - Brightness Handling
    
    private func handleBrightnessChange(display: Int, brightness: Double) {
        NSLog("Received Lunar brightness event: brightness=\(brightness), display=\(String(describing: display))")
        let targetScreenUUID: String?
       
        targetScreenUUID = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDirectDisplayID(number.uint32Value) == CGDirectDisplayID(display)
        }?.displayUUID
        
        // Handle lunar "sub-zero" dimming: Lunar may return negative brightness values to indicate sub-zero dimming.
        let isSubZero = brightness < 0
        let normalizedBrightness = isSubZero ? brightness + 1.0 : brightness
        let iconString: String = isSubZero ? "moon.circle" : ""
        let accentColor: Color? = isSubZero ? Color(red: 1, green: 0.443, blue: 0.509) : nil

        Task { @MainActor in
            BoringViewCoordinator.shared.toggleSneakPeek(
                status: true,
                type: .brightness,
                value: CGFloat(normalizedBrightness),
                icon: iconString,
                accent: accentColor,
                targetScreenUUID: targetScreenUUID
            )
        }
    }
    
    fileprivate func handleLunarEvent(_ event: BNLunarBrightnessEvent) {
        handleBrightnessChange(
            display: event.display,
            brightness: event.brightness
        )
    }

    fileprivate func handleLunarStreamStopped(reason: String?) {
        Task { @MainActor in
            self.isListening = false
            if reason != nil {
                self.isLunarAvailable = false
            }
        }
    }
}

@objc final class LunarEventListener: NSObject, BoringNotchXPCHelperLunarListener {
    weak var manager: LunarManager?

    init(manager: LunarManager) {
        self.manager = manager
        super.init()
    }

    func lunarEventDidUpdate(_ event: BNLunarBrightnessEvent) {
        manager?.handleLunarEvent(event)
    }

    func lunarStreamDidStop(_ reason: String?) {
        manager?.handleLunarStreamStopped(reason: reason)
    }
}
