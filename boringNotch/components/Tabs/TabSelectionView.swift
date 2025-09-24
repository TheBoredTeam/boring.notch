//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI
import Defaults

struct TabModel {
    let label: String
    let icon: String
    let view: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.enableNotes) private var notesEnabled
    @Default(.enableClipboardHistory) private var clipboardEnabled
    @Namespace var animation
    var body: some View {
        let tabs = availableTabs
        HStack(spacing: 0) {
            ForEach(tabs, id: \.view) { tab in
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
        .onAppear { sanitizeSelection(for: tabs) }
        .onChange(of: notesEnabled) { _ in sanitizeSelection(for: availableTabs) }
        .onChange(of: clipboardEnabled) { _ in sanitizeSelection(for: availableTabs) }
    }

    private var availableTabs: [TabModel] {
        var items: [TabModel] = [
            TabModel(label: "Home", icon: "house.fill", view: .home),
            TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
        ]
        if notesEnabled {
            items.append(TabModel(label: "Notes", icon: "note.text", view: .notes))
        }
        if clipboardEnabled {
            items.append(TabModel(label: "Clipboard", icon: "doc.on.clipboard", view: .clipboard))
        }
        return items
    }

    private func sanitizeSelection(for tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if !tabs.contains(where: { $0.view == coordinator.currentView }) {
            if let fallback = tabs.first?.view {
                withAnimation(.smooth) {
                    coordinator.currentView = fallback
                }
            }
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
