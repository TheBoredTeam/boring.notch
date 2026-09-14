//
//  BluetoothActivity.swift
//  boringNotch
//

import SwiftUI

/// Connection / disconnection activity for Bluetooth accessories.
///
/// Follows the same geometry as the other closed-notch activities: content on either side
/// of a black spacer the width of the physical notch.
struct BluetoothActivity: View {
    @EnvironmentObject var vm: BoringViewModel

    let devices: [BluetoothDeviceInfo]
    let isDisconnection: Bool
    let notchHeight: CGFloat

    private var symbol: String {
        guard devices.count == 1, let name = devices.first?.name.lowercased() else {
            return "dot.radiowaves.left.and.right"
        }
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("headphone") || name.contains("headset") || name.contains("buds") {
            return "headphones"
        }
        if name.contains("mouse") { return "magicmouse" }
        if name.contains("keyboard") { return "keyboard" }
        if name.contains("trackpad") { return "magictrackpad" }
        if name.contains("speaker") { return "hifispeaker" }
        return "dot.radiowaves.left.and.right"
    }

    var body: some View {
        HStack(spacing: 0) {
            // The slot is as wide as the status side opposite it, so leaving the icon on its
            // own here strands most of it as empty space against the outer edge.
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .foregroundStyle(.white)
                    .imageScale(.medium)

                // A batch has no single icon or name to speak for it, so say how many.
                if devices.count > 1 {
                    Text("\(devices.count) devices")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else if let name = devices.first?.name {
                    // Runtime data, so verbatim: it must not be picked up as a
                    // localization key. No fixedSize either — the slot has to truncate it.
                    Text(verbatim: name)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(width: activitySlotWidth, alignment: .trailing)

            // The spacer only needs to clear a physical notch. On displays without one it
            // is dead space that pushes the two labels to opposite ends of the bar.
            Rectangle()
                .fill(.black)
                .frame(width: vm.hasNotch ? vm.closedNotchSize.width + activityNotchClearance : 16)

            HStack(spacing: 6) {
                if let battery = devices.first?.battery, !isDisconnection {
                    BluetoothBatteryLabels(battery: battery)
                } else {
                    Text(isDisconnection ? "Disconnected" : "Connected")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(width: activitySlotWidth, alignment: .leading)
        }
        .frame(height: notchHeight, alignment: .center)
    }
}

/// Renders whichever battery readings the accessory actually provided.
struct BluetoothBatteryLabels: View {
    let battery: BluetoothDeviceBattery

    var body: some View {
        HStack(spacing: 6) {
            if let left = battery.left {
                label("L", left)
            }
            if let right = battery.right {
                label("R", right)
            }
            if let casePercent = battery.casePercent {
                label("C", casePercent)
            }
            if battery.left == nil, battery.right == nil, battery.casePercent == nil,
               let single = battery.single
            {
                Text("\(single)%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.gray)
                    .monospacedDigit()
            }
        }
    }

    private func label(_ prefix: String, _ percent: Int) -> some View {
        HStack(spacing: 2) {
            Text(prefix)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(percent)%")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.gray)
                .monospacedDigit()
        }
    }
}

#Preview {
    VStack(spacing: 4) {
        // Connected, with split battery readings.
        BluetoothActivity(
            devices: [
                BluetoothDeviceInfo(
                    address: "00-11-22-33-44-55",
                    name: "AirPods Pro",
                    battery: BluetoothDeviceBattery(single: nil, left: 82, right: 79, casePercent: 64)
                )
            ],
            isDisconnection: false,
            notchHeight: 32
        )

        // Disconnection: no battery to show, so the status word takes the right slot.
        BluetoothActivity(
            devices: [
                BluetoothDeviceInfo(address: "00-11-22-33-44-55", name: "AirPods Pro", battery: nil)
            ],
            isDisconnection: true,
            notchHeight: 32
        )

        // A name too long for the slot, to check it truncates rather than overflowing.
        BluetoothActivity(
            devices: [
                BluetoothDeviceInfo(
                    address: "00-11-22-33-44-66",
                    name: "Bose QuietComfort Ultra Headphones",
                    battery: nil
                )
            ],
            isDisconnection: false,
            notchHeight: 32
        )

        // A batch falls back to the count.
        BluetoothActivity(
            devices: [
                BluetoothDeviceInfo(address: "00-11-22-33-44-55", name: "AirPods Pro", battery: nil),
                BluetoothDeviceInfo(address: "00-11-22-33-44-77", name: "Magic Mouse", battery: nil)
            ],
            isDisconnection: false,
            notchHeight: 32
        )
    }
    .background(Color.black)
    .environmentObject(BoringViewModel())
}
