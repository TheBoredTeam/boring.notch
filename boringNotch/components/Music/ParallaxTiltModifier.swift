// ParallaxTiltModifier.swift — 3D tilt effect on hover for album art

import SwiftUI

struct ParallaxTiltModifier: ViewModifier {
    @State private var rotationX: Double = 0
    @State private var rotationY: Double = 0
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(rotationX),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.5
            )
            .rotation3DEffect(
                .degrees(rotationY),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
            .shadow(
                color: .black.opacity(isHovering ? 0.4 : 0),
                radius: isHovering ? 12 : 0,
                x: CGFloat(-rotationY * 0.5),
                y: CGFloat(rotationX * 0.5)
            )
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: rotationX)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: rotationY)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    isHovering = true
                    let centerX = location.x - 45
                    let centerY = location.y - 45
                    rotationY = Double(centerX / 45) * 12
                    rotationX = Double(-centerY / 45) * 12
                case .ended:
                    isHovering = false
                    rotationX = 0
                    rotationY = 0
                }
            }
    }
}
