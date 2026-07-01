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
    @Default(.boringShelf) private var boringShelf
    @Default(.aiChatEnabled) private var aiChatEnabled

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @StateObject private var shelfState = ShelfStateViewModel.shared
    @Namespace var animation
    private let tabSwitchAnimation = NotchPanelAnimation.spring

    private var visibleTabs: [TabModel] {
        var items: [TabModel] = [
            TabModel(label: "Home", icon: "house.fill", view: .home)
        ]

        if boringShelf && (!shelfState.isEmpty || coordinator.alwaysShowTabs) {
            items.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        if aiChatEnabled {
            items.append(TabModel(label: "AI", icon: "sparkles", view: .assistant))
        }

        return items
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                    withAnimation(tabSwitchAnimation) {
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
        .padding(3)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .onAppear(perform: normalizeSelection)
        .onChange(of: aiChatEnabled) { _, _ in
            normalizeSelection()
        }
        .onChange(of: boringShelf) { _, _ in
            normalizeSelection()
        }
        .onChange(of: shelfState.isEmpty) { _, _ in
            normalizeSelection()
        }
    }

    private func normalizeSelection() {
        if !visibleTabs.contains(where: { $0.view == coordinator.currentView }) {
            coordinator.currentView = .home
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
