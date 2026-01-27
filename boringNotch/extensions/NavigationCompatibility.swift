//
//  NavigationCompatibility.swift
//  boringNotch
//
//  Navigation compatibility layer for macOS 12 (Monterey) support.
//

import SwiftUI

// MARK: - Compatible Navigation Split View

/// A wrapper that uses NavigationSplitView on macOS 13+ and NavigationView on macOS 12.
struct CompatibleNavigationSplitView<Sidebar: View, Detail: View>: View {
    let sidebar: Sidebar
    let detail: Detail
    let sidebarWidth: CGFloat

    init(
        sidebarWidth: CGFloat = 200,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebarWidth = sidebarWidth
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        if #available(macOS 13.0, *) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(sidebarWidth)
            } detail: {
                detail
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationView {
                sidebar
                    .frame(minWidth: sidebarWidth, idealWidth: sidebarWidth, maxWidth: sidebarWidth)
                detail
            }
            .navigationViewStyle(.columns)
        }
    }
}

// MARK: - Toolbar Compatibility

extension View {
    /// Removes sidebar toggle from toolbar on macOS 14+. No-op on older versions.
    @ViewBuilder
    func compatibleToolbarRemovingSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

// MARK: - Scroll Target Compatibility

extension View {
    /// Applies scrollTargetLayout on macOS 14+. No-op on older versions.
    @ViewBuilder
    func compatibleScrollTargetLayout() -> some View {
        if #available(macOS 14.0, *) {
            self.scrollTargetLayout()
        } else {
            self
        }
    }

    /// Applies scrollTargetBehavior on macOS 14+. No-op on older versions.
    @ViewBuilder
    func compatibleScrollTargetBehavior() -> some View {
        if #available(macOS 14.0, *) {
            self.scrollTargetBehavior(.viewAligned)
        } else {
            self
        }
    }
}
