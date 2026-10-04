//
//  BluetoothAccessoryView.swift
//  boringNotch
//
//  Closed-notch banner shown when a Bluetooth accessory connects or disconnects.
//

import SwiftUI

struct BluetoothAccessoryView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var accessories = BluetoothAccessoryManager.shared

    var body: some View {
        if let event = accessories.lastEvent {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: event.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(event.isConnected ? .white : .gray)
                        .frame(width: 20)
                    Text(event.name)
                        .font(.subheadline)
                        .foregroundStyle(event.isConnected ? .white : .gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: 150, alignment: .leading)

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width + 10)

                Group {
                    if !event.isConnected {
                        Text("Disconnected")
                            .foregroundStyle(.gray)
                    } else if let level = event.battery.primary {
                        AccessoryBatteryLabel(level: level, battery: event.battery)
                    } else {
                        Text("Connected")
                            .foregroundStyle(.white)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 150, alignment: .trailing)
            }
            .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
            .animation(.smooth, value: event)
        }
    }
}

private struct AccessoryBatteryLabel: View {
    let level: Int
    let battery: AccessoryBattery

    private var tint: Color {
        level <= 20 ? .red : (level <= 40 ? .yellow : .green)
    }

    private var symbol: String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let left = battery.left, let right = battery.right, left != right {
                Text("L \(left)%  R \(right)%")
                    .monospacedDigit()
                    .foregroundStyle(.white)
            } else {
                Text("\(level)%")
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
    }
}
