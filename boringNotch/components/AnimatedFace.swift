//
//  AnimatedFace.swift
//
//  Modified by Mohd. Azeem Khan on 30/03/2026.
//

import SwiftUI

struct MinimalFaceFeatures: View {
    @State private var pulse = false
    @State private var rotate = false

    var body: some View {
        ZStack {
            // Outer red HUD ring
            Circle()
                .stroke(Color.red.opacity(0.65), lineWidth: 1.2)
                .frame(width: 34, height: 34)
                .scaleEffect(pulse ? 1.05 : 0.95)
                .shadow(color: .red.opacity(0.4), radius: 3)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)

            // Inner red glow
            Circle()
                .fill(Color.red.opacity(0.16))
                .frame(width: 28, height: 28)
                .blur(radius: 6)
                .scaleEffect(pulse ? 1.2 : 0.85)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)

            // Rotating blue tech arc
            Circle()
                .trim(from: 0.05, to: 0.72)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.2),
                            Color.cyan,
                            Color.blue.opacity(0.9)
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 30, height: 30)
                .rotationEffect(.degrees(rotate ? 360 : 0))
                .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: rotate)

            // Spider-Man image
            Image("spiderman")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .clipShape(Circle())
                .shadow(color: .red.opacity(0.8), radius: 4)
        }
        .frame(width: 36, height: 36)
        .offset(x:3)
        .onAppear {
            pulse = true
            rotate = true
        }
    }
}

struct MinimalFaceFeatures_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            MinimalFaceFeatures()
        }
        .previewLayout(.fixed(width: 80, height: 80))
    }
}
