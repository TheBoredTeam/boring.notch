//  NotchPillView.swift
//  IslandNotch
//
//  Purpose: The resting / collapsed pill shown when the shelf is empty or idle
//           (and the visual fallback on Macs without a physical notch).
//  Layer: View

import SwiftUI

struct NotchPillView: View {
    var count: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 12, weight: .semibold))
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(.black.opacity(0.85)))
        .animation(Motion.notchOpen, value: count)
        .help("IslandNotch — capture a screenshot for your coding agent")
    }
}
