//
//  FocusTimerView.swift
//  boringNotch
//
//  Timer tab and the countdown shown in the closed notch.
//

import Defaults
import SwiftUI

struct FocusTimerView: View {
    @ObservedObject var timer = FocusTimerManager.shared

    var body: some View {
        HStack(spacing: 24) {
            ring
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 12) {
                phasePicker

                HStack(spacing: 10) {
                    controlButton(icon: timer.isRunning ? "pause.fill" : "play.fill", size: 40, prominent: true) {
                        timer.toggle()
                    }
                    controlButton(icon: "arrow.counterclockwise", help: "Reset") {
                        timer.reset()
                    }
                    controlButton(icon: "plus", help: "Add a minute") {
                        timer.addMinute()
                    }
                    controlButton(icon: "forward.end.fill", help: "Skip to next") {
                        timer.skip()
                    }
                }

                sessionDots
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 8)
            Circle()
                .trim(from: 0, to: timer.progress)
                .stroke(Color.effectiveAccent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: timer.progress)
            VStack(spacing: 2) {
                Text(timer.formattedRemaining)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text(timer.phase.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            .foregroundStyle(.white)
        }
    }

    private var phasePicker: some View {
        HStack(spacing: 4) {
            ForEach(FocusTimerManager.Phase.allCases) { phase in
                Button {
                    withAnimation(.smooth) { timer.select(phase) }
                } label: {
                    Label(phase.rawValue, systemImage: phase.icon)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(timer.phase == phase ? .white : .gray)
                        .background(Capsule().fill(timer.phase == phase ? Color.white.opacity(0.15) : .clear))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sessionDots: some View {
        let interval = max(1, Defaults[.sessionsBeforeLongBreak])
        let filled = timer.completedFocusSessions % interval
        return HStack(spacing: 6) {
            ForEach(0..<interval, id: \.self) { index in
                Circle()
                    .fill(index < filled ? Color.effectiveAccent : Color.white.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
            Text("\(timer.completedFocusSessions) focus session\(timer.completedFocusSessions == 1 ? "" : "s") done")
                .font(.caption2)
                .foregroundStyle(.gray)
        }
    }

    private func controlButton(icon: String, size: CGFloat = 30, prominent: Bool = false, help: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(prominent ? .black : .white)
                .frame(width: size, height: size)
                .background(Circle().fill(prominent ? Color.white : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Countdown shown beside the hardware notch while the panel is closed.
struct FocusTimerLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var timer = FocusTimerManager.shared

    static let sideWidth: CGFloat = 48

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: timer.isRunning ? timer.phase.icon : "pause.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: Self.sideWidth)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Text(timer.formattedRemaining)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: Self.sideWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}
