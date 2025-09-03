//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI
import Defaults

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.enableStatsFeature) var enableStatsFeature
    @Namespace var animation
    
    // Dynamic tabs based on settings
    private var availableTabs: [TabModel] {
        var baseTabs = [
            TabModel(label: "Home", icon: "house.fill", view: .home),
            TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
        ]
        
        // Only include stats if enabled
        if enableStatsFeature {
            baseTabs.append(TabModel(label: "Stats", icon: "chart.line.uptrend.xyaxis", view: .stats))
        }
        
        return baseTabs
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(availableTabs) { tab in
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
        .onChange(of: enableStatsFeature) { newValue in
            // If stats is disabled and currently selected, switch to home
            if !newValue && coordinator.currentView == .stats {
                withAnimation(.smooth) {
                    coordinator.currentView = .home
                }
            }
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
