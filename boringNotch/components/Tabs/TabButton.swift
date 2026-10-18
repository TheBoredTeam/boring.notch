// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    static let width = NotchTabStripMetrics.buttonWidth
    let label: String
    let icon: String
    let selected: Bool
    var iconImage: NSImage? = nil
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            TabIcon(symbol: icon, image: iconImage)
                .frame(width: Self.width, height: NotchTabStripMetrics.buttonHeight)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The same bounded glyph is used in the strip and its native overflow menu.
struct TabIcon: View {
    let symbol: String
    var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: symbol)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        Log.general.debug("Tapped")
    }
}
