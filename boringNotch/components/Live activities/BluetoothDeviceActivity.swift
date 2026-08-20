//
//  BluetoothDeviceActivity.swift
//  boringNotch
//
//  Created by Claude on 2026-07-05.
//

import Defaults
import SwiftUI

struct BluetoothDeviceActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var bluetoothManager = BluetoothDeviceManager.shared

    var body: some View {
        if let event = bluetoothManager.lastEvent {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: event.iconName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.effectiveAccent)
                        .transition(.scale.combined(with: .opacity))
                    Text(event.name)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 140, alignment: .leading)
                }

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width + 10)

                HStack(spacing: 8) {
                    if Defaults[.bluetoothActivityShowPercentage] && event.hasBatteryInfo {
                        if let left = event.leftPercent, let right = event.rightPercent {
                            budLevel(label: "L", percent: left)
                            budLevel(label: "R", percent: right)
                        } else if let percent = event.batteryPercent ?? event.leftPercent ?? event.rightPercent {
                            Text("\(percent)%")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(levelColor(percent))
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .frame(width: 90, alignment: .trailing)
            }
            .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        }
    }

    private func budLevel(label: String, percent: Int) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.gray)
            Text("\(percent)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(levelColor(percent))
        }
    }

    private func levelColor(_ percent: Int) -> Color {
        if percent <= 20 { return .red }
        if percent <= 40 { return .yellow }
        return .green
    }
}
