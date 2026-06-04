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
    
    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                // A fixed, equal pill per tab — icons differ in intrinsic width
                // (house vs sparkles), so padding-based sizing made the gaps look
                // uneven. A uniform frame gives an even rhythm and a tidy selected pill.
                .frame(width: 36, height: 26)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
