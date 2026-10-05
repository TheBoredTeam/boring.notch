//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI

struct TabModel: Identifiable {
    var id: String { label }
    let label: String
    let icon: String
    let view: NotchViews
}

import Defaults

/// Home and Shelf are always listed; HUD modules appear only when enabled.
var tabs: [TabModel] {
    var result = [
        TabModel(label: "Home", icon: "house.fill", view: .home),
        TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
    ]
    if Defaults[.developerHUDEnabled] { result.append(TabModel(label: "Dev", icon: "hammer.fill", view: .developer)) }
    if Defaults[.githubHUDEnabled] { result.append(TabModel(label: "GitHub", icon: "chevron.left.forwardslash.chevron.right", view: .github)) }
    return result
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.developerHUDEnabled) private var developerHUDEnabled
    @Default(.githubHUDEnabled) private var githubHUDEnabled
    @Namespace var animation
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
    BoringHeader().environmentObject(BoringViewModel(camera: CameraModel()))
}
