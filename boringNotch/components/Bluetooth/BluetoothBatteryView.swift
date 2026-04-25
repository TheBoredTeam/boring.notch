//
//  BluetoothBatteryView.swift
//  boringNotch
//
//  Created by boringNotch contributors on 2026-04-19.
//

import Defaults
import SwiftUI

/// Compact view for showing Bluetooth device battery in the notch header
struct BluetoothBatteryHeaderView: View {
    @ObservedObject var btManager = BluetoothBatteryManager.shared
    @State private var showDeviceList = false

    var body: some View {
        if let device = btManager.devices.first {
            Button(action: {
                if btManager.devices.count > 0 {
                    showDeviceList.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    // Device icon
                    Image(systemName: device.deviceType.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))

                    if device.batteryLevel >= 0 {
                        // Battery level + mini bar
                        HStack(spacing: 4) {
                            Text("\(device.batteryLevel)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                            Text("%")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))

                            // Mini battery bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(.white.opacity(0.1))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(batteryColor(device.batteryLevel))
                                        .frame(width: geo.size.width * Double(device.batteryLevel) / 100)
                                }
                            }
                            .frame(width: 16, height: 4)
                        }
                    } else {
                        Text("--")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDeviceList, arrowEdge: .bottom) {
                BluetoothDeviceListView()
            }
            .help(device.name + (device.batteryLevel >= 0 ? " — \(device.batteryLevel)%" : ""))
        }
    }

    private func batteryColor(_ level: Int) -> Color {
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return .green
    }
}

/// Popover view showing all connected Bluetooth devices with battery info
struct BluetoothDeviceListView: View {
    @ObservedObject var btManager = BluetoothBatteryManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Bluetooth Devices")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    btManager.refreshDevices()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if btManager.devices.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No connected devices")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(btManager.devices) { device in
                    HStack(spacing: 10) {
                        // Device icon in circle
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.08))
                                .frame(width: 32, height: 32)
                            Image(systemName: device.deviceType.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)

                            if device.batteryLevel >= 0 {
                                HStack(spacing: 6) {
                                    // Full-width battery bar
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(.white.opacity(0.08))
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            deviceBatteryColor(device.batteryLevel)
                                                                .opacity(0.7),
                                                            deviceBatteryColor(device.batteryLevel),
                                                        ],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(
                                                    width: geo.size.width
                                                        * CGFloat(device.batteryLevel) / 100)
                                        }
                                    }
                                    .frame(height: 6)

                                    Text("\(device.batteryLevel)%")
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, alignment: .trailing)
                                }
                            } else {
                                Text("Battery unavailable")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 280)
        .foregroundColor(.white)
    }

    private func deviceBatteryColor(_ level: Int) -> Color {
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        if level <= 50 { return .yellow }
        return .green
    }
}
