import SwiftUI

struct OrbPulse: View {
    var intensified: Bool = false
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Kairo.Palette.orbCore.opacity(intensified ? 0.7 : 0.45), .clear],
                    center: .center, startRadius: 0, endRadius: 60
                )
            )
            .scaleEffect(animate ? 1.12 : 1.0)
            .opacity(animate ? 1.0 : 0.6)
            .animation(
                .easeInOut(duration: intensified ? 1.0 : 2.4).repeatForever(autoreverses: true),
                value: animate
            )
            .onAppear { animate = true }
    }
}
