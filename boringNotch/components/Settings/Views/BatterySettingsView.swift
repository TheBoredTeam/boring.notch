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
                .settingsSearchAnchor(SearchKey.indicator)
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("Show power status notifications")
                }
                .settingsSearchAnchor(SearchKey.powerStatusNotifications)
            } header: {
                Text("General")
            }
            Section {
                Defaults.Toggle(key: .showBatteryPercentage) {
                    Text("Show battery percentage")
                }
                .settingsSearchAnchor(SearchKey.percentage)
                Defaults.Toggle(key: .showPowerStatusIcons) {
                    Text("Show power status icons")
                }
                .settingsSearchAnchor(SearchKey.powerStatusIcons)
                Defaults.Toggle(key: .showChargingWattage) {
                    Text("Show charging wattage")
                }
                .settingsSearchAnchor(SearchKey.chargingWattage)
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

extension BatterySettingsView {
    enum SearchKey: String, SettingsSearchKey {
        case indicator
        case powerStatusNotifications
        case percentage
        case powerStatusIcons
        case chargingWattage

        static let tab = SettingsTab.battery

        var definition: SettingsSearchDefinition<Self> {
            switch self {
            case .indicator: .init("Show battery indicator", section: "General")
            case .powerStatusNotifications: .init("Show power status notifications", section: "General")
            case .percentage: .init("Show battery percentage", section: "Battery Information")
            case .powerStatusIcons: .init("Show power status icons", section: "Battery Information")
            case .chargingWattage: .init("Show charging wattage", section: "Battery Information")
            }
        }
    }
}
