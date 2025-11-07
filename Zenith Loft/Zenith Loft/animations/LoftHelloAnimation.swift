//
//  LoftHelloAnimation.swift
//  Zenith Loft
//
//  Created by You on 11/05/25.
//  Part of LoftOS — A Dynamic Notch Experience
//

import SwiftUI

// MARK: - A clean, original glow stroke helper for any Shape
extension Shape {
    /// Draws a glowing stroke by layering a crisp stroke with two blurred strokes.
    func loftGlowStroke(
        _ fill: some ShapeStyle,
        lineWidth: CGFloat = 6,
        blurRadius: CGFloat = 8,
        lineCap: CGLineCap = .round
    ) -> some View {
        self
            .stroke(style: StrokeStyle(lineWidth: lineWidth / 2, lineCap: lineCap))
            .fill(fill)
            .overlay {
                self
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
                    .fill(fill).blur(radius: blurRadius)
            }
            .overlay {
                self
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
                    .fill(fill).blur(radius: blurRadius / 2)
            }
    }
}

// MARK: - Loft rainbow gradient
extension ShapeStyle where Self == LinearGradient {
    static var loftRainbow: LinearGradient {
        LinearGradient(
            colors: [.blue, .purple, .red, .mint, .indigo, .pink, .blue],
            startPoint: .leading, endPoint: .trailing
        )
    }
}

// MARK: - Original wave path (no external coordinates)
/// A smooth sine-wave across the rect.
/// `amplitude` is a 0...1 factor of height, `frequency` is number of full waves.
struct LoftWaveShape: Shape {
    var amplitude: CGFloat = 0.25
    var frequency: CGFloat = 1.0

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let midY = h * 0.5
        let amp = max(0, min(1, amplitude)) * (h * 0.5)

        var p = Path()
        let steps = max(80, Int(w / 4)) // enough segments for a smooth curve

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = t * w
            let y = midY + amp * sin(2 * .pi * frequency * t)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else      { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

// MARK: - A trimmed, animatable glowing segment that travels along a Shape
struct LoftGlowingSegment<Content: Shape, Fill: ShapeStyle>: View, Animatable {
    var progress: Double      // 0...1
    var tail: Double = 0.18   // length of the lit segment (0...1)
    var fill: Fill
    var lineWidth: CGFloat = 8
    var blurRadius: CGFloat = 8
    @ViewBuilder var shape: () -> Content

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let start = max(0, progress - tail)
        let end   = min(1, progress)
        shape()
            .trim(from: start, to: end)
            .loftGlowStroke(fill, lineWidth: lineWidth, blurRadius: blurRadius)
    }
}

// MARK: - Previewable “Hello” animation using the wave + glowing segment
struct LoftHelloAnimation: View {
    @State private var progress: Double = 0

    var body: some View {
        LoftGlowingSegment(
            progress: progress,
            tail: 0.22,
            fill: .loftRainbow,
            lineWidth: 8,
            blurRadius: 8
        ) {
            LoftWaveShape(amplitude: 0.30, frequency: 1.35)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.0)) {
                progress = 1.0
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - SwiftUI preview
#Preview {
    LoftHelloAnimation()
        .frame(width: 300, height: 100)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding()
}
