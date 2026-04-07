// WavySlider.swift — Android 14 style wavy/squiggly music progress bar
// The played portion renders as an animated sine wave that flows,
// the unplayed portion is a flat line.

import SwiftUI

struct WavyTrackShape: Shape {
    var progress: CGFloat      // 0...1
    var amplitude: CGFloat     // wave height in points
    var frequency: CGFloat     // number of complete waves across full width
    var phase: CGFloat         // horizontal offset (animated)

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, phase) }
        set {
            progress = newValue.first
            phase = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let midY = rect.midY
        let progressWidth = rect.width * progress
        var path = Path()

        guard progressWidth > 0 else { return path }

        path.move(to: CGPoint(x: 0, y: midY))

        // Wavy portion (played)
        let step: CGFloat = 1.0
        for x in stride(from: 0, through: progressWidth, by: step) {
            let relativeX = x / rect.width
            // Amplitude fades in at the start and fades out near the progress edge
            let fadeIn = min(x / 20.0, 1.0)
            let fadeOut = min((progressWidth - x) / 15.0, 1.0)
            let localAmplitude = amplitude * fadeIn * fadeOut
            let y = midY + sin((relativeX * frequency * .pi * 2) + phase) * localAmplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }

        return path
    }
}

struct WavyUnplayedTrackShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let midY = rect.midY
        let startX = rect.width * progress
        var path = Path()

        guard startX < rect.width else { return path }

        path.move(to: CGPoint(x: startX, y: midY))
        path.addLine(to: CGPoint(x: rect.width, y: midY))

        return path
    }
}

struct WavySlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    @State private var phase: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height: CGFloat = dragging ? 12 : 8
            let rangeSpan = range.upperBound - range.lowerBound
            let progress = rangeSpan == .zero ? 0 : CGFloat((value - range.lowerBound) / rangeSpan)

            ZStack {
                // Unplayed track (flat line)
                WavyUnplayedTrackShape(progress: progress)
                    .stroke(Color.gray.opacity(0.3), style: StrokeStyle(
                        lineWidth: dragging ? 4 : 3,
                        lineCap: .round
                    ))

                // Played track (wavy)
                WavyTrackShape(
                    progress: progress,
                    amplitude: dragging ? 5 : 3.5,
                    frequency: 3.5,
                    phase: phase
                )
                .stroke(color, style: StrokeStyle(
                    lineWidth: dragging ? 4 : 3,
                    lineCap: .round,
                    lineJoin: .round
                ))

                // Thumb dot at the progress edge
                Circle()
                    .fill(color)
                    .frame(width: dragging ? 10 : 6, height: dragging ? 10 : 6)
                    .position(
                        x: progress * width,
                        y: height / 2
                    )
                    .shadow(color: color.opacity(0.4), radius: dragging ? 4 : 2)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation(.spring(response: 0.2)) {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        withAnimation(.spring(response: 0.3)) {
                            dragging = false
                        }
                        lastDragged = Date()
                    }
            )
            .onAppear {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            phase = .pi * 2
        }
    }
}
