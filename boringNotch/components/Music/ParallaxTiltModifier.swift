// ParallaxTiltModifier.swift — 3D tilt effect on hover for album art

import SwiftUI

struct ParallaxTiltModifier: ViewModifier {
    @State private var rotationX: Double = 0
    @State private var rotationY: Double = 0
    @State private var isHovering = false
    @State private var viewSize: CGSize = .init(width: 90, height: 90)

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear { viewSize = geo.size }
                }
            )
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
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: isHovering)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    isHovering = true
                    let halfW = viewSize.width / 2
                    let halfH = viewSize.height / 2
                    rotationY = Double((location.x - halfW) / halfW) * 12
                    rotationX = Double(-(location.y - halfH) / halfH) * 12
                case .ended:
                    isHovering = false
                    rotationX = 0
                    rotationY = 0
                }
            }
    }
}
