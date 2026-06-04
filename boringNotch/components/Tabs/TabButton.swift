//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    let onClick: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                // A fixed, equal pill per tab — icons differ in intrinsic width
                // (house vs sparkles), so padding-based sizing made the gaps look
                // uneven. A uniform frame gives an even rhythm and a tidy selected pill.
                .frame(width: 36, height: 26)
                .contentShape(Capsule())
                // Hover affordance on the *unselected* tabs only — the selected tab
                // already wears the pill. (macOS pointer is always fine for hover.)
                .background(
                    Capsule().fill(Color.white.opacity(hovering && !selected ? 0.08 : 0))
                )
        }
        // Scale-on-press so a tap feels heard, even before the pill slides.
        .buttonStyle(PressStyle(scale: 0.92, reduceMotion: reduceMotion))
        .onHover { isHovering in
            withAnimation(Motion.resolved(Motion.hover, reduceMotion: reduceMotion)) {
                hovering = isHovering
            }
        }
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
