//
//  BoringBluetoothPopup.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-09.
//
//  iOS-style "device connected" popup shown in the closed notch.
//

import SwiftUI

struct BoringBluetoothPopup: View {
    @EnvironmentObject var vm: BoringViewModel
    let device: BluetoothDeviceInfo

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: device.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(device.name)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Connected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            HStack(spacing: 4) {
                if let battery = device.batteryPercent {
                    Image(systemName: batterySymbol(battery))
                        .foregroundStyle(battery <= 20 ? .red : .green)
                    Text("\(battery)%")
                        .font(.callout)
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 76, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
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
