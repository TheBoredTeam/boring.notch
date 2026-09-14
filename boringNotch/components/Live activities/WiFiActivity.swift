//
//  WiFiActivity.swift
//  boringNotch
//

import SwiftUI

/// Connection / disconnection activity for Wi-Fi.
///
/// Follows the same geometry as the other closed-notch activities: content on either side
/// of a black spacer the width of the physical notch.
///
/// Both details it can show are permission-gated — the network name needs Location
/// authorization, and the signal reading may come back as CoreWLAN's zero sentinel — so
/// every combination of them being absent is a normal state to render, not an error.
struct WiFiActivity: View {
    @EnvironmentObject var vm: BoringViewModel

    let network: WiFiNetworkInfo
    let isDisconnection: Bool
    let notchHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: isDisconnection ? "wifi.slash" : "wifi")
                    .foregroundStyle(.white)
                    .imageScale(.medium)

                if let ssid = network.ssid, !ssid.isEmpty {
                    // Runtime data, so verbatim: it must not be picked up as a
                    // localization key. No fixedSize either — the slot has to truncate it.
                    Text(verbatim: ssid)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    // Not a failure state: this is what every build shows until the user
                    // opts into Location access.
                    Text("Wi-Fi")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .frame(width: activitySlotWidth, alignment: .trailing)

            // The spacer only needs to clear a physical notch. On displays without one it
            // is dead space that pushes the two labels to opposite ends of the bar.
            Rectangle()
                .fill(.black)
                .frame(width: vm.hasNotch ? vm.closedNotchSize.width + activityNotchClearance : 16)

            HStack(spacing: 6) {
                if let strength = network.strength, !isDisconnection {
                    WiFiSignalLabel(strength: strength)
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

/// Signal strength as the same glyph the user already reads in the menu bar.
///
/// A variable-value symbol rather than a percentage: RSSI is logarithmic, so any dBm-to-%
/// curve is invented, and every vendor invents a different one.
struct WiFiSignalLabel: View {
    let strength: WiFiSignalStrength

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "wifi", variableValue: strength.variableValue)
                .imageScale(.small)
                .foregroundStyle(.gray)

            Text(LocalizedStringKey(strength.labelKey))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.gray)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

#Preview {
    VStack(spacing: 4) {
        // Every signal bucket, to check the glyph actually differentiates them.
        ForEach(Array(WiFiSignalStrength.allCases.enumerated()), id: \.offset) { _, strength in
            WiFiActivity(
                network: WiFiNetworkInfo(ssid: "HomeNet-5G", strength: strength),
                isDisconnection: false,
                notchHeight: 32
            )
        }

        // No Location access and no signal reading: the shipping default.
        WiFiActivity(
            network: WiFiNetworkInfo(ssid: nil, strength: nil),
            isDisconnection: false,
            notchHeight: 32
        )

        // A name too long for the slot, to check it truncates rather than overflowing.
        WiFiActivity(
            network: WiFiNetworkInfo(ssid: "Pretty Fly For A Wi-Fi Guest Network", strength: .good),
            isDisconnection: false,
            notchHeight: 32
        )

        // A drop never shows signal, even if the last reading is still around.
        WiFiActivity(
            network: WiFiNetworkInfo(ssid: "HomeNet-5G", strength: .excellent),
            isDisconnection: true,
            notchHeight: 32
        )
    }
    .background(Color.black)
    .environmentObject(BoringViewModel())
}
