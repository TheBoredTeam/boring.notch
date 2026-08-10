//
//  BluetoothConnectionMonitor.swift
//  boringNotch
//

import CoreBluetooth
import Foundation
import IOBluetooth

/// Registers for IOBluetooth connect/disconnect notifications and owns `CBCentralManager` for adapter state.
final class BluetoothConnectionMonitor: NSObject {
    var onDeviceConnected: ((IOBluetoothDevice) -> Void)?
    var onDeviceDisconnected: ((IOBluetoothDevice) -> Void)?
    var onCentralStateChanged: ((CBManagerState) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var centralManager: CBCentralManager?

    func startMonitoring() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(handleDeviceConnected(_:device:))
        )
        centralManager = CBCentralManager(delegate: self, queue: nil)
        registerDisconnectForCurrentlyConnectedPairedDevices()
    }

    func stopMonitoring() {
        connectNotification?.unregister()
        connectNotification = nil
        centralManager?.stopScan()
        centralManager?.delegate = nil
        centralManager = nil
    }

    private func registerDisconnectForCurrentlyConnectedPairedDevices() {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }
        for device in devices where device.isConnected() {
            device.register(forDisconnectNotification: self, selector: #selector(handleDeviceDisconnected(_:device:)))
        }
    }

    @objc private func handleDeviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(handleDeviceDisconnected(_:device:)))
        onDeviceConnected?(device)
    }

    @objc private func handleDeviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onDeviceDisconnected?(device)
    }
}

extension BluetoothConnectionMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onCentralStateChanged?(central.state)
        switch central.state {
        case .poweredOn:
            print("Bluetooth usable (permission granted)")
        case .unauthorized:
            print("Bluetooth permission denied")
        case .poweredOff:
            print("Bluetooth off")
        default:
            break
        }
    }
}
