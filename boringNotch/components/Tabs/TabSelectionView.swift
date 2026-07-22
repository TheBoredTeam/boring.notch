//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let view: NotchViews
    let label: String
    let icon: String

    var id: NotchViews { view }
}

enum NotchTabBar {
    /// Tabs shown when the notch is open (Home always; Shelf when enabled).
    static func tabs(showShelf: Bool) -> [TabModel] {
        var result: [TabModel] = [
            TabModel(view: .home, label: "Home", icon: "house.fill")
        ]
        if showShelf {
            result.append(TabModel(view: .shelf, label: "Shelf", icon: "tray.fill"))
        }
        return result
    }

    static func shouldShowTabBar(
        boringShelf: Bool,
        shelfHasItems: Bool,
        alwaysShowTabs: Bool
    ) -> Bool {
        return boringShelf && (shelfHasItems || alwaysShowTabs)
    }
}

struct TabSelectionView: View {
    @Namespace private var animation
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) private var boringShelf

    private var tabs: [TabModel] {
        NotchTabBar.tabs(showShelf: boringShelf)
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
        .onChange(of: boringShelf) { _, enabled in
            if !enabled, coordinator.currentView == .shelf {
                coordinator.currentView = .home
            }
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
