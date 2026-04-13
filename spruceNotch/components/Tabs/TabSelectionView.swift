//
//  TabSelectionView.swift
//  spruceNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let label: String
    let icon: String
    let view: NotchViews

    var id: NotchViews { view }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = SpruceViewCoordinator.shared
    @Default(.steadyCheckInEnabled) private var steadyCheckInEnabled
    @Default(.spruceShelf) private var spruceShelfEnabled
    @Namespace var animation

    private var tabs: [TabModel] {
        var t: [TabModel] = [
            TabModel(label: "Home", icon: "house.fill", view: .home)
        ]
        if spruceShelfEnabled {
            t.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        if steadyCheckInEnabled {
            t.append(TabModel(label: "Check-in", icon: "checkmark.circle.fill", view: .steadyCheckIn))
        }
        return t
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
    SpruceHeader().environmentObject(SpruceViewModel())
}
