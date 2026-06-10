//
//  WidgetsView.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-09.
//
//  Container for the Widgets tab (system monitor, weather, device batteries,
//  rates). All enabled widgets share the width equally so each stays visible.
//

import Defaults
import SwiftUI

struct WidgetsView: View {
    @Default(.enableSystemMonitor) var enableSystemMonitor
    @Default(.enableWeatherWidget) var enableWeatherWidget
    @Default(.enableDeviceBatteryWidget) var enableDeviceBatteryWidget
    @Default(.enableRatesWidget) var enableRatesWidget

    private var enabledCount: Int {
        [enableSystemMonitor, enableWeatherWidget, enableDeviceBatteryWidget, enableRatesWidget]
            .filter { $0 }.count
    }

    var body: some View {
        Group {
            if enabledCount == 0 {
                Text("No widgets enabled")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: enabledCount > 2 ? 8 : 15) {
                    if enableSystemMonitor {
                        SystemMonitorView().frame(maxWidth: .infinity)
                    }
                    if enableWeatherWidget {
                        WeatherWidgetView().frame(maxWidth: .infinity)
                    }
                    if enableDeviceBatteryWidget {
                        DeviceBatteriesView().frame(maxWidth: .infinity)
                    }
                    if enableRatesWidget {
                        RatesWidgetView().frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
