//
//  BoringLowBatteryAlert.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-10.
//
//  iOS-style low-battery alert shown on the closed notch when the charge
//  drops to 10% and again at 5% (battery power only).
//

import SwiftUI

struct BoringLowBatteryAlert: View {
    @EnvironmentObject var vm: BoringViewModel

    var levelBattery: Float
    var isInLowPowerMode: Bool

    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "battery.25")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.red)
                    .opacity(pulse ? 1.0 : 0.35)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Low battery")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text("\(Int(levelBattery))% remaining")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            HStack {
                BatteryView(
                    levelBattery: levelBattery,
                    isPluggedIn: false,
                    isCharging: false,
                    isInLowPowerMode: isInLowPowerMode,
                    batteryWidth: 30,
                    isForNotification: true
                )
            }
            .frame(width: 76, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onDisappear {
            pulse = false
        }
    }
}
