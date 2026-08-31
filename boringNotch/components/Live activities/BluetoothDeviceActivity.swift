//
//  BluetoothDeviceActivity.swift
//  boringNotch
//
//  Adapted from Cris2907/not-so-boring-notch.
//

import SwiftUI

struct BluetoothDeviceActivity: View {
    let device: BluetoothAudioDevice?
    let profile: BluetoothHeadphoneProfile
    let closedNotchWidth: CGFloat
    let height: CGFloat

    private var iconSize: CGFloat {
        max(18, min(34, height - 10))
    }

    private var deviceName: String {
        guard let device else { return profile.displayName }
        return profile.resolvedDisplayName(for: device)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: profile.symbolName)
                    .font(.system(size: iconSize * 0.72, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: iconSize, height: iconSize)

                MarqueeText(
                    .constant(deviceName),
                    textColor: .white,
                    minDuration: 1,
                    frameWidth: 128
                )
                .font(.caption)
                .fontWeight(.medium)
            }
            .frame(width: 174, alignment: .leading)
            .padding(.leading, 8)

            Rectangle()
                .fill(.black)
                .frame(width: closedNotchWidth + 10)

            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Connected")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.gray)
            }
            .frame(width: 92, alignment: .trailing)
            .padding(.trailing, 8)
        }
        .frame(height: height, alignment: .center)
        .background(alignment: .leading) {
            LinearGradient(
                colors: [.cyan.opacity(0.22), .green.opacity(0.14), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .blur(radius: 14)
            .opacity(0.8)
        }
    }
}
