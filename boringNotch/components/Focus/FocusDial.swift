//
//  FocusDial.swift
//  boringNotch
//
//  The circular timer dial: a tick-marked ring with the elapsed arc drawn on
//  it and the primary control in the middle.
//

import SwiftUI

/// Palette for the focus surface. Warm rather than the monitor's cool card
/// grey — a focus timer should read as a different mode of the notch, not as
/// another readout.
enum FocusPalette {
    static let panel = Color.white.opacity(0.04)
    static let border = Color.white.opacity(0.07)
    static let track = Color.white.opacity(0.10)
    static let tick = Color.white.opacity(0.22)
    static let work = Color(red: 0.898, green: 0.400, blue: 0.220)
    static let shortBreak = Color(red: 0.204, green: 0.780, blue: 0.349)
    static let longBreak = Color(red: 0.204, green: 0.600, blue: 0.918)
    static let label = Color.white.opacity(0.45)
    static let secondary = Color.white.opacity(0.6)

    static func tint(for phase: FocusPhase) -> Color {
        switch phase {
        case .work: return work
        case .shortBreak: return shortBreak
        case .longBreak: return longBreak
        }
    }
}

/// The dial. Ticks are labelled in minutes of the *current phase*, so a
/// 5-minute break shows 1…5 rather than a 60-minute face with a sliver
/// filled — the reference design's fixed 0–60 face only reads correctly for
/// a 60-minute timer.
struct FocusDial: View {
    let phase: FocusPhase
    let progress: Double
    let remaining: TimeInterval
    let totalDuration: TimeInterval
    let isIdle: Bool
    let isPaused: Bool
    let onToggle: () -> Void

    var diameter: CGFloat = 132

    @State private var isHovering = false

    private var tint: Color { FocusPalette.tint(for: phase) }

    /// Five evenly spaced labels around the face. More than that is unreadable
    /// at this size; fewer loses the sense of a clock.
    private var tickLabels: [(angle: Double, text: String)] {
        let steps = 5
        let minutes = max(1, Int((totalDuration / 60).rounded()))
        return (1...steps).map { step in
            let fraction = Double(step) / Double(steps)
            return (
                angle: fraction * 360 - 90,
                text: "\(Int((Double(minutes) * fraction).rounded()))"
            )
        }
    }

    var body: some View {
        ZStack {
            tickMarks
            ring
            centreControl
        }
        .frame(width: diameter, height: diameter)
        .overlay { tickText }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(FocusPalette.track, lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Linear, not spring: a timer arc that overshoots and settles
                // reads as inaccurate even when the number beside it is right.
                .animation(.linear(duration: 0.3), value: progress)
        }
        .padding(18)
    }

    private var tickMarks: some View {
        ForEach(0..<60, id: \.self) { index in
            let isMajor = index % 5 == 0
            Capsule()
                .fill(FocusPalette.tick.opacity(isMajor ? 1 : 0.45))
                .frame(width: isMajor ? 1.5 : 1, height: isMajor ? 5 : 3)
                .offset(y: -(diameter / 2) + 24)
                .rotationEffect(.degrees(Double(index) / 60 * 360))
        }
        .accessibilityHidden(true)
    }

    private var tickText: some View {
        ForEach(tickLabels, id: \.angle) { label in
            Text(label.text)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(FocusPalette.label)
                .monospacedDigit()
                .offset(
                    x: (diameter / 2 + 8) * cos(label.angle * .pi / 180),
                    y: (diameter / 2 + 8) * sin(label.angle * .pi / 180)
                )
        }
        .accessibilityHidden(true)
    }

    private var centreControl: some View {
        Button(action: onToggle) {
            VStack(spacing: 1) {
                Text(primaryLabel)
                    .font(.system(size: isIdle ? 15 : 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(secondaryLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(FocusPalette.secondary)
            }
            .frame(width: diameter - 60, height: diameter - 60)
            .background(
                Circle()
                    .fill(Color.black.opacity(isHovering ? 0.25 : 0.4))
                    .overlay(Circle().stroke(tint.opacity(isHovering ? 0.6 : 0.25), lineWidth: 1))
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
    }

    private var primaryLabel: String {
        isIdle
            ? NSLocalizedString("focus_start", comment: "Focus dial button: start the timer")
            : FocusTimeFormatter.countdown(remaining)
    }

    private var secondaryLabel: String {
        if isIdle { return FocusTimeFormatter.minutesLabel(totalDuration) }
        if isPaused { return NSLocalizedString("focus_paused", comment: "Focus dial subtitle when paused") }
        return phase.localizedTitle
    }

    /// Spoken as a sentence: the dial's two stacked labels are a typographic
    /// split, not two separate pieces of information.
    private var accessibilityLabel: String {
        if isIdle {
            return String(
                format: NSLocalizedString("focus_a11y_start", comment: "VoiceOver: start a focus session of N minutes"),
                FocusTimeFormatter.minutesLabel(totalDuration)
            )
        }
        let state = isPaused
            ? NSLocalizedString("focus_paused", comment: "Focus dial subtitle when paused")
            : phase.localizedTitle
        return "\(state), \(FocusTimeFormatter.countdown(remaining))"
    }
}
