// WavySlider.swift — Android 14 style wavy/squiggly music progress bar
// The played portion renders as an animated sine wave that flows,
// the unplayed portion is a flat line.

import SwiftUI

struct WavyTrackShape: Shape {
    var progress: CGFloat      // 0...1
    var amplitude: CGFloat     // wave height in points (0 = flat line)
    var frequency: CGFloat     // number of complete waves across full width
    var phase: CGFloat         // horizontal offset (animated)

    // Only progress + phase animate; amplitude snaps on pause/resume so the
    // phase's repeatForever animation isn't interrupted by transition work.
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
        let step: CGFloat = 2.0
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
    // When false the wave flattens into a straight line (paused playback).
    var isPlaying: Bool = true
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    // One full phase cycle (0 -> 2π) takes this many seconds.
    private let phasePeriod: TimeInterval = 1.2

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let midY = geometry.size.height / 2
            let rangeSpan = range.upperBound - range.lowerBound
            // Clamp to 0...1 so out-of-range playback values (e.g. transient overshoot
            // from estimatedPlaybackPosition while seeking) don't paint past the track.
            let rawProgress = rangeSpan == .zero ? 0 : CGFloat((value - range.lowerBound) / rangeSpan)
            let progress = max(0, min(1, rawProgress))
            // Wave flattens to 0 amplitude when paused and ripples back on play.
            let targetAmplitude: CGFloat = {
                if dragging { return 5 }
                return isPlaying ? 3.5 : 0
            }()

            // TimelineView drives the phase off wall-clock time, so rapid state
            // changes (drags, value updates) can't cancel or slow the animation
            // the way a repeatForever withAnimation can.
            TimelineView(.animation) { timeline in
                let phase = phaseFor(time: timeline.date)

                ZStack {
                    // Unplayed track (flat line)
                    WavyUnplayedTrackShape(progress: progress)
                        .stroke(Color.gray.opacity(0.3), style: StrokeStyle(
                            lineWidth: dragging ? 4 : 3,
                            lineCap: .round
                        ))

                    // Played track (wavy while playing, flat when paused)
                    WavyTrackShape(
                        progress: progress,
                        amplitude: targetAmplitude,
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
                            y: midY
                        )
                        .shadow(color: color.opacity(0.4), radius: dragging ? 4 : 2)
                }
            }
            // Expand hit area to the full GeometryReader rect so clicks don't miss a
            // thin 8pt wave. Shapes still render at midY of whatever frame we're given.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = true
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
        }
    }

    private func phaseFor(time: Date) -> CGFloat {
        let t = time.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: phasePeriod)
        return CGFloat(t / phasePeriod) * .pi * 2
    }
}
