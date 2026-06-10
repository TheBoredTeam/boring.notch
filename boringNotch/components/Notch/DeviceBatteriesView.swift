//
//  DeviceBatteriesView.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-10.
//
//  Battery levels of connected Bluetooth devices (AirPods, mice, keyboards)
//  for the Widgets tab. Reads the IORegistry via BluetoothBatteryReader.
//

import SwiftUI

struct DeviceBatteriesView: View {
    @State private var devices: [DeviceBattery] = []
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "battery.75")
                Text("Devices")
                    .font(.headline)
            }
            .foregroundStyle(.white)

            if devices.isEmpty {
                Text("No devices connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(devices) { device in
                    HStack(spacing: 6) {
                        Image(systemName: device.iconName)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .frame(width: 16)
                        Text(device.name)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: batterySymbol(device.percent))
                            .font(.caption2)
                            .foregroundStyle(device.percent <= 20 ? .red : .green)
                        Text("\(device.percent)%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .onAppear {
            refresh()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                refresh()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func refresh() {
        // IORegistry reads are cheap but not free; keep them off the main thread.
        DispatchQueue.global(qos: .utility).async {
            let result = BluetoothBatteryReader.allDevices()
            DispatchQueue.main.async { devices = result }
        }
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
