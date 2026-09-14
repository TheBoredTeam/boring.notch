//
//  BatterySettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import SwiftUI

struct Charge: View {
    @Default(.lowBatteryWarning) var lowBatteryWarning
    @Default(.lowBatteryThreshold) var lowBatteryThreshold
    @ObservedObject private var batteryModel = BatteryStatusViewModel.shared

    private let thresholds = [30, 25, 20, 15, 10, 5]

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
                Defaults.Toggle(key: .lowBatteryWarning) {
                    Text("Show low battery warning")
                }
                Picker("Threshold", selection: $lowBatteryThreshold) {
                    ForEach(thresholds, id: \.self) { value in
                        Text("\(value)%").tag(value)
                    }
                }
                .disabled(!lowBatteryWarning)

                if !batteryModel.hasBattery {
                    HelpText("This Mac does not have a battery.")
                }
            } header: {
                Text("Low Battery")
            } footer: {
                Text("Warns once when the battery drops to the threshold, and again only after it has charged back up.")
            }
            .disabled(!batteryModel.hasBattery)
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
