//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    // Stable id (one tab per view) so the selection capsule animates correctly when the tab list is rebuilt.
    var id: NotchViews { view }
    let label: String
    let icon: String
    let view: NotchViews
}

/// Tabs currently available in the open notch, based on which features are enabled.
var tabs: [TabModel] {
    var result = [TabModel(label: "Home", icon: "house.fill", view: .home)]
    if Defaults[.boringShelf] {
        result.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
    }
    if Defaults[.enablePomodoro] {
        result.append(TabModel(label: "Pomodoro", icon: "timer", view: .pomodoro))
    }
    return result
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    // Observed so the tab list refreshes as soon as these are toggled in Settings.
    @Default(.boringShelf) private var boringShelf
    @Default(.enablePomodoro) private var enablePomodoro
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
    BoringHeader().environmentObject(BoringViewModel())
}
