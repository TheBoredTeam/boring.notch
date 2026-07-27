//
//  BluetoothManager.swift
//  boringNotch
//
//  Created by Murat ŞENOL on 20.11.2025.
//

import CoreBluetooth
import Defaults
import Foundation
import IOBluetooth
import SwiftUI

/// Composes `BluetoothConnectionMonitor` (connectivity) and battery/metadata services for the UI.
final class BluetoothManager: ObservableObject {

    static let shared = BluetoothManager()

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Published private(set) var deviceSnapshot: BluetoothDeviceSnapshot?
    @Published private(set) var isInitialized: Bool = false
    @Published private(set) var bluetoothState: CBManagerState = .unknown

    @Published private(set) var audioDeviceSnapshot: BluetoothDeviceSnapshot?

    private let connectionMonitor = BluetoothConnectionMonitor()
    private var batteryFetchTask: Task<Void, Never>?
    private var audioBatteryFetchTask: Task<Void, Never>?

    var deviceIconSymbolName: String {
        guard let snapshot = deviceSnapshot else {
            return BluetoothDeviceIconResolver.fallbackSymbolName
        }
        return BluetoothDeviceIconResolver.sfSymbolName(
            for: snapshot,
            customMappings: Defaults[.bluetoothDeviceIconMappings]
        )
    }

    private init() {
        connectionMonitor.onDeviceConnected = { [weak self] device in
            self?.handleDeviceConnected(device)
        }
        connectionMonitor.onDeviceDisconnected = { [weak self] device in
            self?.handleDeviceDisconnected(device)
        }
        connectionMonitor.onCentralStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.bluetoothState = state
            }
        }
    }

    deinit {
        batteryFetchTask?.cancel()
        audioBatteryFetchTask?.cancel()
        connectionMonitor.stopMonitoring()
    }

    func initializeBluetooth() {
        guard !isInitialized else { return }
        connectionMonitor.startMonitoring()
        
        // Pick up already connected audio devices on startup
        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in devices where device.isConnected() {
                if device.deviceClassMajor == 4 { // Audio
                    handleDeviceConnected(device)
                }
            }
        }
        
        isInitialized = true
    }

    private func handleDeviceConnected(_ device: IOBluetoothDevice) {
        Task { @MainActor in
            guard let address = device.addressString, let name = device.name else { return }
            deviceSnapshot = BluetoothDeviceSnapshot(
                address: address,
                name: name,
                isConnected: true,
                batteryPercentage: nil,
                minorDeviceClass: nil
            )
            if device.deviceClassMajor == 4 {
                audioDeviceSnapshot = deviceSnapshot
            }
        }
        startBatteryPolling(for: device)
    }

    private func handleDeviceDisconnected(_ device: IOBluetoothDevice) {
        batteryFetchTask?.cancel()
        if device.deviceClassMajor == 4 {
            audioBatteryFetchTask?.cancel()
        }
        Task { @MainActor in
            guard let address = device.addressString, let name = device.name else { return }
            let minorToKeep = (self.deviceSnapshot?.address == address) ? self.deviceSnapshot?.minorDeviceClass : nil
            let snapshot = BluetoothDeviceSnapshot(
                address: address,
                name: name,
                isConnected: false,
                batteryPercentage: nil,
                minorDeviceClass: minorToKeep
            )
            self.deviceSnapshot = snapshot
            if self.audioDeviceSnapshot?.address == address {
                self.audioDeviceSnapshot = nil // Clear audio snapshot if it disconnected
            }
            self.coordinator.toggleExpandingView(status: true, type: .bluetooth)
        }
    }

    private func startBatteryPolling(for device: IOBluetoothDevice) {
        let isAudio = device.deviceClassMajor == 4
        if isAudio {
            audioBatteryFetchTask?.cancel()
        } else {
            batteryFetchTask?.cancel()
        }

        guard let deviceName = device.name,
              let deviceAddress = device.addressString else { return }

        let task = Task.detached { [weak self] in
            guard let self else { return }

            let percentage = await BluetoothPeripheralBatteryService.pollUntilBatteryPercentageFound(
                deviceName: deviceName,
                deviceAddress: deviceAddress
            )

            let minorClass = await BluetoothDeviceMetadata.fetchMinorDeviceClass(deviceName: deviceName)

            await MainActor.run {
                if self.deviceSnapshot?.address == deviceAddress {
                    self.deviceSnapshot = BluetoothDeviceSnapshot(
                        address: deviceAddress,
                        name: deviceName,
                        isConnected: true,
                        batteryPercentage: percentage,
                        minorDeviceClass: minorClass
                    )
                }
                
                if isAudio, self.audioDeviceSnapshot?.address == deviceAddress {
                    self.audioDeviceSnapshot = BluetoothDeviceSnapshot(
                        address: deviceAddress,
                        name: deviceName,
                        isConnected: true,
                        batteryPercentage: percentage,
                        minorDeviceClass: minorClass
                    )
                }
                
                self.coordinator.toggleExpandingView(status: true, type: .bluetooth)
            }
        }
        
        if isAudio {
            audioBatteryFetchTask = task
        } else {
            batteryFetchTask = task
        }
    }
}
