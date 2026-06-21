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

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Focus", icon: "timer", view: .pomodoro),
    TabModel(label: "System", icon: "cpu", view: .system),
    TabModel(label: "Projects", icon: "hammer.fill", view: .projects),
    TabModel(label: "Note", icon: "square.and.pencil", view: .note),
    TabModel(label: "Launch", icon: "square.grid.2x2.fill", view: .launcher)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.tabsMulticolor) private var multicolor
    @Namespace var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                let selected = coordinator.currentView == tab.view
                TabButton(label: tab.label, icon: tab.icon, selected: selected) {
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                .foregroundStyle(iconColor(for: tab.view, selected: selected))
                .background {
                    Capsule()
                        .fill(capsuleFill)
                        .matchedGeometryEffect(id: "capsule", in: animation)
                        .opacity(selected ? 1 : 0)
                }
            }
        }
        .clipShape(Capsule())
    }

    // Distinct hue per tab, used when "multicolor icons" is enabled.
    private func tabColor(_ v: NotchViews) -> Color {
        switch v {
        case .home:     return Color(red: 0.30, green: 0.62, blue: 1.00) // blue
        case .shelf:    return Color(red: 1.00, green: 0.62, blue: 0.25) // orange
        case .pomodoro: return Color(red: 1.00, green: 0.45, blue: 0.45) // red
        case .system:   return Color(red: 0.40, green: 0.85, blue: 0.55) // green
        case .projects: return Color(red: 1.00, green: 0.82, blue: 0.30) // yellow
        case .note:     return Color(red: 0.70, green: 0.55, blue: 1.00) // purple
        case .launcher: return Color(red: 0.30, green: 0.80, blue: 0.80) // teal
        }
    }

    private func iconColor(for v: NotchViews, selected: Bool) -> Color {
        if multicolor {
            return selected ? tabColor(v) : tabColor(v).opacity(0.5)
        }
        return selected ? .white : .gray
    }

    // Multicolor mode keeps a neutral capsule so the icon hue reads; otherwise
    // the selected capsule carries the accent tint.
    private var capsuleFill: Color {
        multicolor ? Color.white.opacity(0.14) : Color.effectiveAccent.opacity(0.30)
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
