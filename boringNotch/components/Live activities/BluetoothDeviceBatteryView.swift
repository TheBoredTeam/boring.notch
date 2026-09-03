//
//  BluetoothDeviceBatteryView.swift
//  boringNotch
//
//  Created for Bluetooth Input Device Battery Display
//

import SwiftUI
import Defaults

/// Compact view showing Bluetooth device batteries in the notch header
struct BluetoothDeviceBatteryView: View {
    @ObservedObject private var bluetoothManager = BluetoothDeviceManager.shared
    
    var body: some View {
        if Defaults[.showBluetoothDeviceBattery] && !bluetoothManager.devicesWithBattery.isEmpty {
            HStack(spacing: 6) {
                ForEach(bluetoothManager.devicesWithBattery) { device in
                    DeviceBatteryItem(device: device)
                }
            }
        }
    }
}

/// Single device battery indicator
private struct DeviceBatteryItem: View {
    let device: BluetoothInputDevice
    
    private var batteryColor: Color {
        guard let level = device.batteryLevel else { return .gray }
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return .green
    }
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: device.deviceType.iconName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            
            if let battery = device.batteryLevel {
                Text("\(battery)%")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(batteryColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(.black.opacity(0.3))
        }
        .help("\(device.name): \(device.batteryLevel ?? 0)%")
    }
}

#Preview {
    BluetoothDeviceBatteryView()
        .padding()
        .background(Color.gray)
}
