//
//  HoverButton.swift
//  boringNotch
//
//  Created by Kraigo on 04.09.2024.
//

import SwiftUI

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect;
    
    @State private var isHovering = false

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)
        // The large play/pause button is wider than its neighbors but its icon
        // only fills the middle. The empty edges used to be tappable and would
        // swallow taps meant for the adjacent ±15s skip buttons. Shrink the hit
        // shape on large buttons so the wrong-button trap becomes a small dead
        // zone instead.
        let hitWidthRatio: CGFloat = (scale == .large) ? 0.7 : 1.0

        Button(action: action) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle().scale(x: hitWidthRatio, y: 1.0))
                .frame(width: size, height: size)
                .overlay {
                    Capsule()
                        .fill(isHovering ? Color.gray.opacity(0.2) : .clear)
                        .frame(width: size, height: size)
                        .overlay {
                            Image(systemName: icon)
                                .foregroundColor(iconColor)
                                .contentTransition(contentTransition)
                                .font(scale == .large ? .largeTitle : .body)
                        }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
    }
}
