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
    let view: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var extensionManager = ExtensionManager.shared
    @Namespace var animation
    
    // Generate tabs from extension manager
    var visibleTabs: [TabModel] {
        var tabList: [TabModel] = []
        
        // Home is always first
        tabList.append(TabModel(id: "home", label: "Home", icon: "house.fill", view: .home))
        
        // Add tabs from .navigationTab extensions
        for ext in extensionManager.tabExtensions() {
            if let tabIcon = ext.tabIcon ?? ext.contentProvider?().tabIcon {
                tabList.append(TabModel(
                    id: ext.id,
                    label: ext.tabTitle ?? ext.contentProvider?().tabTitle ?? ext.name,
                    icon: tabIcon,
                    view: .shelf // Map to shelf for now, could be dynamic later
                ))
            }
        }
        
        return tabList
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

