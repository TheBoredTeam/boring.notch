//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @StateObject private var shelfState = ShelfStateViewModel.shared
    @Default(.showWeather) private var showWeather
    @Default(.boringShelf) private var showShelf
    @Namespace var animation

    private var tabs: [TabModel] {
        var visibleTabs: [TabModel] = [
            TabModel(
                label: NSLocalizedString("Home", comment: "Notch tab label: Home"),
                icon: "house.fill",
                view: .home
            )
        ]

        if showWeather {
            visibleTabs.append(
                TabModel(
                    label: NSLocalizedString("Weather", comment: "Notch tab label: Weather"),
                    icon: "cloud.sun.fill",
                    view: .weather
                )
            )
        }

        if showShelf && (!shelfState.isEmpty || coordinator.alwaysShowTabs) {
            visibleTabs.append(
                TabModel(
                    label: NSLocalizedString("Shelf", comment: "Notch tab label: Shelf"),
                    icon: "tray.fill",
                    view: .shelf
                )
            )
        }

        return visibleTabs
    }

    private func ensureCurrentViewIsVisible() {
        if tabs.contains(where: { $0.view == coordinator.currentView }) {
            return
        }
        coordinator.currentView = .home
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
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
        .onAppear(perform: ensureCurrentViewIsVisible)
        .onChange(of: showWeather) { _, _ in ensureCurrentViewIsVisible() }
        .onChange(of: showShelf) { _, _ in ensureCurrentViewIsVisible() }
        .onChange(of: shelfState.isEmpty) { _, _ in ensureCurrentViewIsVisible() }
        .onChange(of: coordinator.alwaysShowTabs) { _, _ in ensureCurrentViewIsVisible() }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
