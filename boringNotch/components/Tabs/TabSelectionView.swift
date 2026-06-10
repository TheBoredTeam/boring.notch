//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//  Modified by Maksymilian Wójcik on 2026-06-09.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Widgets", icon: "chart.bar.fill", view: .widgets)
]

/// Whether the Widgets tab should be offered (any widget enabled).
var widgetsTabEnabled: Bool {
    Defaults[.enableSystemMonitor] || Defaults[.enableWeatherWidget]
        || Defaults[.enableDeviceBatteryWidget] || Defaults[.enableRatesWidget]
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) var boringShelf
    @Default(.enableSystemMonitor) var enableSystemMonitor
    @Default(.enableWeatherWidget) var enableWeatherWidget
    @Default(.enableDeviceBatteryWidget) var enableDeviceBatteryWidget
    @Default(.enableRatesWidget) var enableRatesWidget
    @Namespace var animation

    private var visibleTabs: [TabModel] {
        tabs.filter { tab in
            switch tab.view {
            case .home: return true
            case .shelf: return boringShelf
            case .widgets:
                return enableSystemMonitor || enableWeatherWidget
                    || enableDeviceBatteryWidget || enableRatesWidget
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
