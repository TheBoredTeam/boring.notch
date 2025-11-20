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

final class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    
    @Published private(set) var isBluetoothConnected: Bool = false
    @Published private(set) var deviceName: String = ""
    @Published private(set) var batteryPercentage: Int? = nil
    
    private var scanTimer: Timer?
    private var audioDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var audioDevicePropertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    private override init() {
        super.init()
        setupAudioDeviceListener()
        checkBluetoothDevices()
        //startPeriodicScanning()
    }
    
    deinit {
        //stopPeriodicScanning()
        removeAudioDeviceListener()
    }
    
    // MARK: - Setup Methods
    
    private func setupAudioDeviceListener() {
        let listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.checkBluetoothDevices()
        }
        
        audioDeviceListenerBlock = listenerBlock
        
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &audioDevicePropertyAddress,
            nil,
            listenerBlock
        )
        
        if status != noErr {
            print("Failed to add audio device listener: \(status)")
        }
    }
    
    private func removeAudioDeviceListener() {
        if let listenerBlock = audioDeviceListenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &audioDevicePropertyAddress,
                nil,
                listenerBlock
            )
            audioDeviceListenerBlock = nil
        }
    }
    
    private func startPeriodicScanning() {
        scanTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkBluetoothDevices()
        }
    }
    
    private func stopPeriodicScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
    }
    
    // MARK: - Device Detection
    
    private func checkBluetoothDevices() {
        // Primary method: Check current audio output device via CoreAudio
        if let audioDevice = getCurrentAudioOutputDevice() {
            if isBluetoothAudioDevice(audioDevice) {
                let name = getAudioDeviceName(audioDevice) ?? ""
                let battery = getBluetoothDeviceBattery(audioDevice)
                updateConnectionStatus(connected: true, deviceName: name, batteryPercentage: battery)
                return
            }
        }
        
        // Fallback: No Bluetooth audio device found
        updateConnectionStatus(connected: false, deviceName: "", batteryPercentage: nil)
    }
    
    // MARK: - CoreAudio Helpers
    
    private func getCurrentAudioOutputDevice() -> AudioObjectID? {
        var defaultDeviceID = kAudioObjectUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultDeviceID
        )
        if status != noErr || defaultDeviceID == kAudioObjectUnknown {
            return nil
        }
        return defaultDeviceID
    }
    
    private func isBluetoothAudioDevice(_ deviceID: AudioObjectID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else {
            return false
        }
        
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &transportType
        )
        
        if status == noErr {
            // Bluetooth transport type is 'blue' (FourCharCode: 0x626C7565)
            let bluetoothTransportType: UInt32 = 0x626C7565 // 'blue'
            return transportType == bluetoothTransportType
        }
        
        return false
    }
    
    private func getAudioDeviceName(_ deviceID: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else {
            return nil
        }
        
        var deviceName: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceName
        )
        
        if status == noErr, let name = deviceName as String? {
            return name
        }
        
        return nil
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
    
    @MainActor
    private func updateConnectionStatus(connected: Bool, deviceName: String, batteryPercentage: Int?) {
        Task { [weak self] in
            guard let self else { return }
            if self.isBluetoothConnected != connected ||
               self.deviceName != deviceName ||
               self.batteryPercentage != batteryPercentage {
                self.isBluetoothConnected = connected
                self.deviceName = deviceName
                self.batteryPercentage = batteryPercentage
                coordinator.toggleExpandingView(status: true, type: .bluetooth)
            }
        }
    }
}

