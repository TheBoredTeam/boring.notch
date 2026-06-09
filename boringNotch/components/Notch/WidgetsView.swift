//
//  WidgetsView.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-09.
//
//  Container for the Widgets tab (system monitor + weather).
//

import Defaults
import SwiftUI

struct WidgetsView: View {
    @Default(.enableSystemMonitor) var enableSystemMonitor
    @Default(.enableWeatherWidget) var enableWeatherWidget

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            if enableSystemMonitor {
                SystemMonitorView()
            }
            if enableWeatherWidget {
                WeatherWidgetView()
            }
            if !enableSystemMonitor && !enableWeatherWidget {
                Text("No widgets enabled")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
