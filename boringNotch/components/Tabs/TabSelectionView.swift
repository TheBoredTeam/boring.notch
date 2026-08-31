//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    var id: NotchViews { view }
    let label: String
    let icon: String
    let view: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @StateObject private var shelfModel = ShelfStateViewModel.shared
    @Default(.timeActivityEnabled) private var timeActivityEnabled
    @Default(.boringShelf) private var boringShelf
    @Namespace var animation

    private var visibleTabs: [TabModel] {
        var result = [TabModel(label: "Home", icon: "house.fill", view: .home)]
        if timeActivityEnabled {
            result.append(TabModel(label: "Timer", icon: "timer", view: .activities))
        }
        if boringShelf && (!shelfModel.isEmpty || coordinator.alwaysShowTabs) {
            result.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                    coordinator.selectView(tab.view)
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
        .animation(
            BoringViewCoordinator.contentTransitionAnimation,
            value: coordinator.currentView
        )
        .onChange(of: timeActivityEnabled) { _, isEnabled in
            guard !isEnabled, coordinator.currentView == .activities else { return }
            coordinator.selectView(.home)
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
