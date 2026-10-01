// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

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
    var iconImage: NSImage? = nil
}

struct TabSelectionView: View {
    enum Presentation {
        case embedded
        case floating(maximumWidth: CGFloat)
    }

    var presentation: Presentation = .embedded
    @Default(.compactMode) private var compactMode
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var registry = ExtensionTabRegistry.shared
    @Default(.boringShelf) private var shelfEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace var animation

    private var tabs: [TabModel] {
        var result = [TabModel(label: "Home", icon: "house.fill", view: .home)]
        if shelfEnabled { result.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)) }
        result += registry.tabs(for: compactMode ? .compact : .regular).map {
            TabModel(label: $0.descriptor.title, icon: $0.systemSymbol, view: .extensionTab($0.id), iconImage: $0.iconImage)
        }
        return result
    }

    var body: some View {
        let tabs = self.tabs
        let selection = coordinator.currentView

        Group {
            switch presentation {
            case .embedded:
                measuredStrip(tabs: tabs, selection: selection)
            case .floating(let maximumWidth):
                measuredStrip(tabs: tabs, selection: selection)
                    .frame(width: NotchTabStripMetrics.floatingContentWidth(tabCount: tabs.count, maximumWidth: maximumWidth))
                    .padding(.horizontal, NotchTabStripMetrics.horizontalPadding)
                    .padding(.vertical, NotchTabStripMetrics.verticalPadding)
                    .background(.black, in: Capsule())
                    .overlay { Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch tabs")
    }

    private func measuredStrip(tabs: [TabModel], selection: NotchViews) -> some View {
        GeometryReader { geometry in
            tabStrip(tabs: tabs, selection: selection,
                     showsOverflow: CGFloat(tabs.count) * TabButton.width > geometry.size.width)
        }
        .frame(height: NotchTabStripMetrics.buttonHeight)
    }

    private func tabStrip(tabs: [TabModel], selection: NotchViews, showsOverflow: Bool) -> some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(tabs) { tab in
                            TabButton(label: tab.label, icon: tab.icon, selected: selection == tab.view, iconImage: tab.iconImage) {
                                select(tab.view)
                            }
                            .frame(height: NotchTabStripMetrics.buttonHeight)
                            .foregroundStyle(tab.view == selection ? .white : .gray)
                            .background {
                                if tab.view == selection {
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
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
                .onChange(of: selection) { _, newSelection in
                    withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(newSelection, anchor: .center) }
                }
            }
            if showsOverflow {
                Menu {
                    Picker("Active tab", selection: Binding(get: { coordinator.currentView }, set: select)) {
                        ForEach(tabs) { tab in
                            Label {
                                Text(tab.label)
                            } icon: {
                                TabIcon(symbol: tab.icon, image: tab.iconImage)
                            }
                            .tag(tab.view)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: NotchTabStripMetrics.buttonHeight)
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
        // A menu can outlive a metadata or mode change. Resolve against the
        // current registry again instead of selecting a stale hidden entry.
        switch tab {
        case .home:
            break
        case .shelf:
            guard Defaults[.boringShelf] else { return }
        case .extensionTab(let id):
            let mode: ExtensionTabPresentation = Defaults[.compactMode] ? .compact : .regular
            guard registry.tab(for: id, presentation: mode) != nil else { return }
        }
        guard coordinator.currentView != tab else { return }
        withAnimation(reduceMotion ? nil : .smooth) { coordinator.currentView = tab }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel(camera: CameraModel()))
}
