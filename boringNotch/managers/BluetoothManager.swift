//
//  BluetoothManager.swift
//  boringNotch
//
//  Created on 2025-01-XX.
//

import AppKit
import Combine
import CoreAudio
import Foundation
import SwiftUI
import IOBluetooth

enum BluetoothConnectionStatus {
    case connected
    case disconnected
}

final class BluetoothManager: NSObject, ObservableObject {
    
    static let shared = BluetoothManager()
    
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Published private(set) var batteryPercentage: Int? = nil
    
    @Published private(set) var lastBluetoothActionStatus: BluetoothConnectionStatus = .disconnected
    @Published private(set) var lastBluetoothDevice: IOBluetoothDevice?
    
    private var notificationCenter: IOBluetoothUserNotification?
    private var connectedDevices: [String : String] = [:]
    
    private override init() {
        super.init()
        registerForConnect()
    }
    
    deinit {
        notificationCenter?.unregister()
    }
    
    private func registerForConnect() {
        // Register for Bluetooth notifications
        notificationCenter = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        
        // Initial check
        checkDevices()
    }
    
    private func checkDevices() {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }
        
        let currentConnected = Set(devices.filter { $0.isConnected() }.compactMap { $0.addressString })
        
        // Find connected devices
        for address in currentConnected {
            if let device = devices.first(where: { $0.addressString == address }),
               let address = device.addressString,
               let name = device.name {
                connectedDevices[address] = name
            }
        }
    }
    
    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        handleDeviceConnected(device)
    }
    
    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        handleDeviceDisconnected(device)
    }
    
    private func handleDeviceConnected(_ device: IOBluetoothDevice) {
        guard let name = device.name, let address = device.addressString else { return }
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        connectedDevices[address] = name
        Task { @MainActor in
            lastBluetoothDevice = device
            lastBluetoothActionStatus = .connected
        }
        coordinator.toggleExpandingView(status: true, type: .bluetooth)
    }
    
    private func handleDeviceDisconnected(_ device: IOBluetoothDevice) {
        Task { @MainActor in
            lastBluetoothDevice = device
            lastBluetoothActionStatus = .disconnected
        }
        coordinator.toggleExpandingView(status: true, type: .bluetooth)
        if let address = device.addressString {
            connectedDevices.removeValue(forKey: address)
        }
    }
    
    private func getBluetoothDeviceBattery(_ deviceID: AudioObjectID) -> Int? {
        // Try to get battery level from audio device properties
        // Note: Not all Bluetooth devices expose battery information through CoreAudio
        // This is a best-effort attempt
        
        // Some devices may expose battery through custom properties
        // For AirPods, macOS may provide battery info through system APIs
        // For now, we'll return nil if not available
        
        // You can extend this to check for specific device properties
        // or use other system APIs for AirPods battery information
        
        return 20 // Placeholder - can be extended with actual battery detection
    }
    
    func getDeviceIcon(for device: IOBluetoothDevice?) -> String {
        // check name first then classOfDevice
        guard let device else { return "circle.badge.questionmark" }
        if let deviceName = device.name, let iconName = sfSymbolForAudioDevice(deviceName) {
            return iconName
        }
        
        let classOfDevice: BluetoothClassOfDevice = device.classOfDevice
        
        let majorClass = (classOfDevice & 0x1F00) >> 8
        let minorClass = (classOfDevice & 0x00FC) >> 2
        
        switch majorClass {
        case 0x01: return "desktopcomputer"
        case 0x02: return "smartphone"
        case 0x04: // Audio/Video
            switch minorClass {
            case 0x01, 0x06: return "headphones"
            case 0x02: return "phone.and.waveform"
            case 0x05: return "hifispeaker.fill"
            default: return "speaker.wave.3.fill"
            }
        case 0x05: // Peripheral
            let keyboardMouse = (minorClass & 0x30) >> 4
            switch keyboardMouse {
            case 0x01: return "keyboard.fill"
            case 0x02: return "computermouse.fill"
            case 0x03: return "keyboard.badge.ellipsis.fill"
            default: return "gamecontroller.fill"
            }
        case 0x06: return "camera"
        case 0x07: return "watch.analog"
        default: return "circle.badge.questionmark"
        }
    }
    
    func sfSymbolForAudioDevice(_ deviceName: String) -> String? {
        let name = deviceName.lowercased()

        // ---- Apple AirPods ----
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("airpods case") { return "airpodschargingcase" }
        // ---- Beats ----
        if name.contains("beats studio buds") { return "beats.studiobuds" }
        if name.contains("beats solo buds") { return "beats.solobuds" }
        if name.contains("beats solo") { return "beats.headphones" }
        if name.contains("beats studio") { return "beats.headphones" }
        if name.contains("powerbeats pro") { return "beats.powerbeats.pro" }
        if name.contains("beats fit pro") { return "beats.fitpro" }
        if name.contains("beats flex") { return "beats.earphones" }
        // ---- General fallback for audio devices ----
        if name.contains("buds") { return "earbuds" }
        if name.contains("headphone") || name.contains("headset") { return "headphones" }
        if name.contains("speaker") { return "hifispeaker.fill" }
        
        // --- Keyboard & Mouse ---
        if name.contains("keyboard") { return "keyboard.fill" }
        if name.contains("mouse") && name.contains("magic") { return "magicmouse.fill" }
        if name.contains("mouse") { return "computermouse.fill" }
        // ---- Gamepads ----
        if name.contains("gamepad") || name.contains("controller") || name.contains("joy-con") { return "gamecontroller.fill" }
        
        return nil
    }
}

