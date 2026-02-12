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
import Combine

final class LunarManager: ObservableObject {
    static let shared = LunarManager()
    
    @Published private(set) var isLunarAvailable: Bool = false
    @Published private(set) var isListening: Bool = false
    
    /// Tracks the last value sent to setLunarOSDHidden to avoid redundant XPC calls.
    private var lastOSDHidden: Bool?
    
    private var eventListener: LunarEventListener?
    private var cancellables: Set<AnyCancellable> = []
    
    private init() {
        refreshAvailability()
        // Restore Lunar OSD when we quit so the user gets it back
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { _ in
                Task {
                    // Always restore on termination regardless of lastOSDHidden
                    _ = await XPCHelperClient.shared.setLunarOSDHidden(false)
                }
            }
            .store(in: &cancellables)
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
    
    /// Asks the XPC helper to write Lunar's hideOSD preference (disable Lunar's OSD when we replace it, restore when we don't).
    func configureLunarOSD(hide: Bool) {
        guard hide != lastOSDHidden else { return }
        lastOSDHidden = hide
        Task { _ = await XPCHelperClient.shared.setLunarOSDHidden(hide) }
    }

    // MARK: - Brightness Handling
    
    private func handleBrightnessChange(display: Int, brightness: Double) {
        NSLog("Received Lunar brightness event: brightness=\(brightness), display=\(String(describing: display))")
        let targetScreenUUID: String?
       
        targetScreenUUID = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDirectDisplayID(number.uint32Value) == CGDirectDisplayID(display)
        }?.displayUUID
        
        // Handle Lunar "sub-zero" dimming and XDR brightness
        let isSubZero = brightness < 0
        let isXDR = brightness > 1.0

        let normalizedBrightness: Double = switch true {
            case isSubZero: max(0, 1 + brightness)
            case isXDR:     min(1, brightness - 1)
            default:        brightness
        }

        let iconString: String = switch true {
            case isSubZero: "moon.circle"
            case isXDR:     "sun.max.circle"
            default:        ""
        }

        let accentColor: Color? = switch true {
            case isSubZero: Color(red: 1,    green: 0.443, blue: 0.509)
            case isXDR:     Color(red: 0.58, green: 0.647, blue: 0.78)
            default:        nil
        }

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
