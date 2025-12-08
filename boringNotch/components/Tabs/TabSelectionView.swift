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
    @ObservedObject var bluetoothManager = BluetoothManager.shared
    @Namespace var animation
    
    private var tabs: [TabModel] {
        var items: [TabModel] = [
            TabModel(label: "Home", icon: "house.fill", view: .home)
        ]
        
        if Defaults[.boringShelf] {
            items.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        
        if bluetoothManager.hasConnectedDevices || coordinator.bluetoothLiveActivityEnabled {
            items.append(
                TabModel(
                    label: "Bluetooth",
                    icon: "dot.radiowaves.left.and.right",
                    view: .bluetooth
                )
            )
        }
        
        return items
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
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
