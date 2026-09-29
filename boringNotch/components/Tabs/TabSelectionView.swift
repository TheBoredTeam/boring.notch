//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    var id: NotchViews { view }
    let label: String
    let icon: String
    let view: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var registry = ExtensionTabRegistry.shared
    @Default(.boringShelf) private var shelfEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace var animation

    private var tabs: [TabModel] {
        var result = [TabModel(label: "Home", icon: "house.fill", view: .home)]
        if shelfEnabled { result.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)) }
        result += registry.tabs.map {
            TabModel(label: $0.descriptor.title, icon: $0.descriptor.systemSymbol, view: .extensionTab($0.id))
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            tabStrip(showsOverflow: CGFloat(tabs.count) * TabButton.width > geometry.size.width)
        }
        .frame(height: 26)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch tabs")
    }

    private func tabStrip(showsOverflow: Bool) -> some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(tabs) { tab in
                            TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                                select(tab.view)
                            }
                            .frame(height: 26)
                            .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                            .background {
                                if tab.view == coordinator.currentView {
                                    Capsule()
                                        .fill(Color(nsColor: .secondarySystemFill))
                                        .matchedGeometryEffect(id: "capsule", in: animation)
                                }
                            }
                            .id(tab.id)
                        }
                    }
                }
                .clipShape(Capsule())
                .onAppear { proxy.scrollTo(coordinator.currentView, anchor: .center) }
                .onChange(of: coordinator.currentView) { _, selection in
                    withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(selection, anchor: .center) }
                }
            }
            if showsOverflow {
                Menu {
                    ForEach(tabs) { tab in
                        Button { select(tab.view) } label: {
                            if tab.view == coordinator.currentView {
                                Label(tab.label, systemImage: "checkmark")
                            } else {
                                Label(tab.label, systemImage: tab.icon)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: 26)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("All tabs")
                .accessibilityLabel("All tabs")
            }
        }
    }

    private func select(_ tab: NotchViews) {
        withAnimation(reduceMotion ? nil : .smooth) { coordinator.currentView = tab }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel(camera: CameraModel()))
}
