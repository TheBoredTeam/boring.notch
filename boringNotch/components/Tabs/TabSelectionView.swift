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
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @StateObject var shelfVM = ShelfStateViewModel.shared
    @Namespace var animation
    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    ZStack(alignment: .topTrailing) {
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
            }
            .clipShape(Capsule())
            
            // Badge for shelf file count
            if !shelfVM.isEmpty {
                Text("\(shelfVM.items.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .offset(x: 5, y: -5)
            }
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
