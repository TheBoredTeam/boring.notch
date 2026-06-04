//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

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
    TabModel(label: "Pi", icon: "sparkles", view: .pi)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                let isSelected = coordinator.currentView == tab.view
                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    // Frequent action → fast snappy spring, not the old ~0.5s `.smooth`.
                    withAnimation(Motion.resolved(Motion.tabSwitch, reduceMotion: reduceMotion)) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                // The selected icon eases white↔gray rather than snapping as the pill slides.
                .foregroundStyle(isSelected ? .white : .gray)
                .background {
                    // Only the selected tab owns the pill; matchedGeometry slides it
                    // between tabs. (Attaching the same id to hidden non-selected copies
                    // is a matchedGeometry anti-pattern — there must be one source.)
                    if isSelected {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
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
