//
//  TimerView.swift
//  boringNotch
//

import SwiftUI

// MARK: - Closed-notch pill shown when timer finishes

struct TimerFinishedPillView: View {
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat
    @State private var flash = false

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Time's up!")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            Rectangle()
                .fill(.black)
                .frame(width: closedNotchWidth + 10)
            HStack {
                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.effectiveAccent)
                    .opacity(flash ? 0.25 : 1.0)
                Spacer()
            }
            .frame(width: 76)
        }
        .frame(height: closedNotchHeight, alignment: .center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                flash = true
            }
        }
    }
}

// MARK: - Presets

private let presets: [(label: String, seconds: TimeInterval)] = [
    ("+1m",  60),
    ("+5m",  300),
    ("+10m", 600),
    ("+25m", 1500),
    ("+45m", 2700),
]

// MARK: - Main timer view

struct TimerView: View {
    @ObservedObject var timerManager = TimerManager.shared

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
                .frame(maxWidth: .infinity)
            rightPanel
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Left: presets + controls

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            presetRow
            controlRow
            Spacer(minLength: 0)
        }
        .padding(.trailing, 10)
    }

    private var presetRow: some View {
        HStack(spacing: 5) {
            ForEach(presets, id: \.label) { preset in
                presetButton(preset)
            }
        }
        .opacity(timerManager.state == .finished ? 0.2 : 1)
        .allowsHitTesting(timerManager.state != .finished)
        .animation(.smooth(duration: 0.2), value: timerManager.state == .finished)
    }

    private func presetButton(_ preset: (label: String, seconds: TimeInterval)) -> some View {
        Button {
            withAnimation(.smooth) { timerManager.addPreset(preset.seconds) }
        } label: {
            Text(preset.label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Capsule().fill(Color(nsColor: .tertiarySystemFill)))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            switch timerManager.state {
            case .idle, .running, .paused:
                primaryButton
                if timerManager.totalDuration > 0 {
                    resetButton
                }
            case .finished:
                newTimerButton
            }
        }
        .animation(.smooth(duration: 0.2), value: timerManager.state)
    }

    private var primaryButton: some View {
        Button {
            withAnimation(.smooth) {
                timerManager.state == .running ? timerManager.pause() : timerManager.start()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: timerManager.state == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(primaryLabel)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(timerManager.state == .idle && timerManager.remainingTime == 0)
        .opacity(timerManager.state == .idle && timerManager.remainingTime == 0 ? 0.3 : 1)
    }

    private var primaryLabel: String {
        switch timerManager.state {
        case .running: return "Pause"
        case .paused:  return "Resume"
        default:       return "Start"
        }
    }

    private var resetButton: some View {
        HoverButton(icon: "arrow.counterclockwise", scale: .medium) {
            withAnimation(.smooth) { timerManager.reset() }
        }
    }

    private var newTimerButton: some View {
        Button {
            withAnimation(.smooth) { timerManager.reset() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                Text("New Timer")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Right: ring + countdown

    private var rightPanel: some View {
        GeometryReader { geo in
            let diameter = min(geo.size.width, geo.size.height) - 4
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: ringFillAmount)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timerManager.progress)
                timeLabel
            }
            .frame(width: diameter, height: diameter)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private var ringFillAmount: CGFloat {
        guard timerManager.totalDuration > 0 else { return 0 }
        return CGFloat(max(0, 1.0 - timerManager.progress))
    }

    private var timeLabel: some View {
        VStack(spacing: 2) {
            Text(formattedTime(timerManager.remainingTime))
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .foregroundColor(timeTextColor)
                .contentTransition(.numericText(countsDown: true))
                .animation(.smooth(duration: 0.3), value: timerManager.remainingTime)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 6)

            if timerManager.state == .finished {
                Text("Done")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.effectiveAccent)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Helpers

    private var timeTextColor: Color {
        if timerManager.state == .finished { return .effectiveAccent }
        if timerManager.totalDuration == 0  { return .white.opacity(0.3) }
        return .white
    }

    private var ringColor: Color {
        switch timerManager.state {
        case .running:  return .effectiveAccent
        case .paused:   return Color.white.opacity(0.35)
        case .finished: return .effectiveAccent
        default:        return Color.white.opacity(0.2)
        }
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let total = Int(ceil(max(0, seconds)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
