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

/// Which tabs the opened notch currently offers.
///
/// Contextual rather than fixed: Home is always there, and the others appear only when they
/// have something to show, so an idle notch stays as bare as it has always been.
enum NotchTabs {
    @MainActor
    static var available: [TabModel] {
        var result = [TabModel(label: "Home", icon: "house.fill", view: .home)]

        if Defaults[.boringShelf],
           !ShelfStateViewModel.shared.isEmpty || BoringViewCoordinator.shared.alwaysShowTabs
        {
            result.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }

        if DownloadActivityManager.shared.hasVisibleActivity {
            result.append(
                TabModel(label: "Downloads", icon: "arrow.down.circle.fill", view: .downloads))
        }

        if PrivacyActivityManager.shared.hasVisibleActivity {
            result.append(TabModel(label: "Privacy", icon: "hand.raised.fill", view: .privacy))
        }

        // Settings-gated rather than contextual: it is reference material the user asks
        // for, not something an event brings into being.
        if Defaults[.showNetworkInformation] {
            result.append(TabModel(label: "System", icon: "cpu", view: .system))
        }

        return result
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var shelf = ShelfStateViewModel.shared
    @ObservedObject var downloadManager = DownloadActivityManager.shared
    @ObservedObject var privacyManager = PrivacyActivityManager.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(NotchTabs.available) { tab in
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
