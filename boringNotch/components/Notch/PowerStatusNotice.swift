//
//  PowerStatusNotice.swift
//  boringNotch
//
//  The closed-notch notice shown when the power source or charging state
//  changes: a label on one side of the notch and the battery on the other.
//

import SwiftUI

struct PowerStatusNotice: View {
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    let notchWidth: CGFloat
    let height: CGFloat

    /// Both sides hold the label and the battery stacked, one of them hidden, so
    /// they always measure the same: the black centre stays under the physical
    /// notch however long the (translated) label is, and the pill is only as
    /// wide as its content.
    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                label
                battery.hidden()
            }
            .frame(minWidth: 76, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: notchWidth + 10)

            ZStack(alignment: .trailing) {
                label.hidden()
                battery
            }
            .frame(minWidth: 76, alignment: .trailing)
        }
        .frame(height: height, alignment: .center)
    }

    private var label: some View {
        Text(batteryModel.statusText)
            .font(.subheadline)
            .foregroundStyle(.white)
            .lineLimit(1)
    }

    private var battery: some View {
        BoringBatteryView(
            batteryWidth: 30,
            isCharging: batteryModel.isCharging,
            isInLowPowerMode: batteryModel.isInLowPowerMode,
            isPluggedIn: batteryModel.isPluggedIn,
            levelBattery: batteryModel.levelBattery,
            maxAdapterWatts: batteryModel.maxAdapterWatts,
            isForNotification: true
        )
    }
}
