//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI
import Defaults

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let notchView: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var extensionManager = ExtensionManager.shared
    @Namespace var animation
    
    // Generate tabs from extension manager
    var visibleTabs: [TabModel] {
        var tabList: [TabModel] = []
        
        // Home is always first
        tabList.append(TabModel(id: "home", label: "Home", icon: "house.fill", notchView: .home))
        
        // Add tabs from .navigationTab extensions
        for ext in extensionManager.tabExtensions() {
            if let tabIcon = ext.tabIcon ?? ext.contentProvider?().tabIcon {
                // Special case: Shelf extension uses the built-in .shelf view
                let targetView: NotchViews = ext.id == "shelf" ? .shelf : .extensionTab(id: ext.id)
                
                tabList.append(TabModel(
                    id: ext.id,
                    label: ext.tabTitle ?? ext.contentProvider?().tabTitle ?? ext.name,
                    icon: tabIcon,
                    notchView: targetView
                ))
            }
        }
        
        return tabList
    }
    
    /// Check if a tab is currently selected
    private func isSelected(_ tab: TabModel) -> Bool {
        coordinator.currentView == tab.notchView
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                TabButton(label: tab.label, icon: tab.icon, selected: isSelected(tab)) {
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.notchView
                    }
                }
                .frame(height: 26)
                .foregroundStyle(isSelected(tab) ? .white : .gray)
                .background {
                    if isSelected(tab) {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "selectedTab", in: animation)
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

