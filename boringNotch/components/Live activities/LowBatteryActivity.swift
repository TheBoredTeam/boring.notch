//
//  LowBatteryActivity.swift
//  boringNotch
//

import SwiftUI

/// The compact low-battery warning shown in the closed notch.
///
/// Laid out like the other closed-notch activities: content is pushed to either side of a
/// black spacer the width of the physical notch, so nothing sits underneath the camera.
struct LowBatteryActivity: View {
    @EnvironmentObject var vm: BoringViewModel

    let level: Int
    let isPluggedIn: Bool
    let isInLowPowerMode: Bool
    let notchHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Text("Low Battery")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: activitySlotWidth, alignment: .trailing)

            // The spacer only needs to clear a physical notch. On displays without one it
            // is dead space that pushes the two labels to opposite ends of the bar.
            Rectangle()
                .fill(.black)
                .frame(width: vm.hasNotch ? vm.closedNotchSize.width + activityNotchClearance : 16)

            HStack(spacing: 5) {
                Text("\(level)%")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    // Carries the urgency regardless of where the user set the threshold —
                    // BatteryView only turns red at its own hardcoded 20%.
                    .foregroundStyle(.red)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                BatteryView(
                    levelBattery: Float(level),
                    isPluggedIn: isPluggedIn,
                    isCharging: false,
                    isInLowPowerMode: isInLowPowerMode,
                    batteryWidth: 30,
                    isForNotification: true
                )
            }
            .frame(width: activitySlotWidth, alignment: .leading)
        }
        .frame(height: notchHeight, alignment: .center)
    }
}

#Preview {
    LowBatteryActivity(level: 18, isPluggedIn: false, isInLowPowerMode: false, notchHeight: 32)
        .background(Color.black)
        .environmentObject(BoringViewModel())
}
