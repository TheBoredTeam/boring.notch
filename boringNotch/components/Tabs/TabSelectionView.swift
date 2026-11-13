//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation

    /// Only tabs the user has switched on in Settings; the music tab is always
    /// present, so this is never empty.
    private var enabledTabs: [NotchViews] {
        NotchViews.enabledViews
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(enabledTabs) { tab in
                    TabButton(label: String(localized: tab.localizedTitle), icon: tab.tabIcon, selected: coordinator.currentView == tab) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab ? Color(nsColor: .secondarySystemFill) : Color.clear)
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
