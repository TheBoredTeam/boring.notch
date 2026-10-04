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

/// Tabs shown in the open notch, filtered by the user's settings.
func enabledTabs() -> [TabModel] {
    var tabs = [TabModel(label: "Home", icon: "house.fill", view: .home)]
    if Defaults[.boringShelf] {
        tabs.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
    }
    if Defaults[.showClipboardTab] {
        tabs.append(TabModel(label: "Clipboard", icon: "doc.on.clipboard", view: .clipboard))
    }
    if Defaults[.showTimerTab] {
        tabs.append(TabModel(label: "Timer", icon: "timer", view: .timer))
    }
    if Defaults[.showNotesTab] {
        tabs.append(TabModel(label: "Notes", icon: "note.text", view: .notes))
    }
    if Defaults[.showTodosTab] {
        tabs.append(TabModel(label: "To-Dos", icon: "checklist", view: .todos))
    }
    return tabs
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    // Observed so the tab bar refreshes when tabs are turned on or off.
    @Default(.boringShelf) private var boringShelf
    @Default(.showClipboardTab) private var showClipboardTab
    @Default(.showTimerTab) private var showTimerTab
    @Default(.showNotesTab) private var showNotesTab
    @Default(.showTodosTab) private var showTodosTab

    var body: some View {
        let tabs = enabledTabs()
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view, horizontalPadding: tabs.count > 4 ? 9 : 15) {
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
