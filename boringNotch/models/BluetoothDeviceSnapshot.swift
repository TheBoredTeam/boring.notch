//
//  BluetoothDeviceSnapshot.swift
//  boringNotch
//

import Foundation

/// UI-facing state for the currently surfaced Bluetooth device (notch, sneak peek, settings).
struct BluetoothDeviceSnapshot: Equatable, Sendable {
    var address: String
    var name: String
    var isConnected: Bool
    var batteryPercentage: Int?
    var minorDeviceClass: String?
}
