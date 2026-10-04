//
//  BatterySettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import SwiftUI

struct BatterySettingsView: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBatteryIndicator) {
                    Text("Show battery indicator")
                }
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("Show power status notifications")
                }
            } header: {
                Text("General")
            }
            Section {
                Defaults.Toggle(key: .showBatteryPercentage) {
                    Text("Show battery percentage")
                }
                Defaults.Toggle(key: .showPowerStatusIcons) {
                    Text("Show power status icons")
                }
                Defaults.Toggle(key: .showChargingWattage) {
                    Text("Show charging wattage")
                }
            } header: {
                Text("Battery Information")
            }
            Section {
                Defaults.Toggle(key: .showBluetoothAccessories) {
                    Text("Show Bluetooth accessory connections")
                }
            } header: {
                Text("Accessories")
            } footer: {
                Text(
                    "Shows AirPods, headphones, keyboards and mice in the notch when they connect, with their battery level when available. macOS will ask for Bluetooth access.",
                    comment: "Footer for the Bluetooth accessory connection setting."
                )
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
        .onAppear {
            Task { @MainActor in
                await XPCHelperClient.shared.isAccessibilityAuthorized()
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Battery")
    }
}
