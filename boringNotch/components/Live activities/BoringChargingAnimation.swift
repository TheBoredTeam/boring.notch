//
//  BoringChargingAnimation.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-09.
//
//  iOS-style charging activity shown on the notch when power is connected.
//

import Defaults
import SwiftUI

/// An iOS-style charging indicator displayed in the closed notch when the
/// power adapter is connected. Mirrors the layout of the battery notification
/// (left info / notch gap / right battery glyph) but emphasises a pulsing
/// green bolt and an animated fill.
struct BoringChargingAnimation: View {
    @EnvironmentObject var vm: BoringViewModel

    var levelBattery: Float
    var isCharging: Bool
    var timeToFullCharge: Int

    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.green)
                    .opacity(pulse ? 1.0 : 0.35)

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(levelBattery))%")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    if timeToFullCharge > 0 {
                        Text("\(timeToFullCharge) min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            HStack {
                BatteryView(
                    levelBattery: levelBattery,
                    isPluggedIn: true,
                    isCharging: isCharging,
                    isInLowPowerMode: false,
                    batteryWidth: 30,
                    isForNotification: true
                )
            }
            .frame(width: 76, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onDisappear {
            pulse = false
        }
    }
}
