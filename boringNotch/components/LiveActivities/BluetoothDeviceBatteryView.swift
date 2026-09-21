//
//  BluetoothDeviceBatteryView.swift
//  boringNotch
//
//  Created for Bluetooth Input Device Battery Display
//

import SwiftUI
import Defaults

// MARK: - BluetoothDeviceBatteryView

/// A compact view displaying battery levels for connected Bluetooth input devices.
///
/// This view shows a horizontal stack of battery indicators for devices like
/// Magic Mouse, Magic Keyboard, and Magic Trackpad. Each device is displayed
/// as a small capsule with an icon and percentage.
///
/// The view automatically hides when:
/// - The `showBluetoothDeviceBattery` setting is disabled
/// - No devices with battery information are available
///
/// ## Usage
/// ```swift
/// // Simply add to your view hierarchy
/// BluetoothDeviceBatteryView()
/// ```
///
/// - Note: This view is currently not used in the header but kept for potential future use.
///         Battery information is displayed in the Battery popover instead.
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

// MARK: - DeviceBatteryItem

/// A single device battery indicator pill/capsule.
///
/// Displays the device type icon and battery percentage in a compact format.
/// The percentage text color changes based on battery level:
/// - Green: > 20%
/// - Orange: 11-20%
/// - Red: ≤ 10%
private struct DeviceBatteryItem: View {
    /// The Bluetooth device to display
    let device: BluetoothInputDevice
    
    /// Determines the battery percentage text color based on charge level
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

// MARK: - Preview

#Preview {
    BluetoothDeviceBatteryView()
        .padding()
        .background(Color.gray)
}
