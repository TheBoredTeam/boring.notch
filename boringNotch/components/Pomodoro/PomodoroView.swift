//
//  PomodoroView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct PomodoroView: View {
    @ObservedObject private var pomodoro = PomodoroManager.shared

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            timerRing
            durationControls
            controlButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 8)
    }

    // MARK: - Timer ring

    private var timerRing: some View {
        ZStack {
            CircularProgressView(
                progress: pomodoro.isRunning || pomodoro.isPaused ? pomodoro.progress : 0,
                color: .effectiveAccent
            )
            .frame(width: 88, height: 88)

            VStack(spacing: 2) {
                Text(pomodoro.formattedRemaining)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text(statusLabel)
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.65))
            }
        }
        .frame(width: 100)
    }

    private var statusLabel: String {
        if pomodoro.isRunning { return "Running" }
        if pomodoro.isPaused { return "Paused" }
        return "Ready"
    }

    // MARK: - Duration controls

    private var durationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Duration")
                .font(.caption)
                .foregroundStyle(Color(white: 0.65))

            presetButtons

            DurationWheelPicker(
                selectedMinutes: Binding(
                    get: { pomodoro.durationMinutes },
                    set: { pomodoro.setDuration(minutes: $0) }
                ),
                isEnabled: pomodoro.canEditDuration
            )
            .frame(width: 110, height: 100)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(pomodoro.canEditDuration ? 1 : 0.45)
        .allowsHitTesting(pomodoro.canEditDuration)
    }

    private var presetButtons: some View {
        HStack(spacing: 8) {
            ForEach(PomodoroManager.presetDurations, id: \.self) { minutes in
                Button {
                    pomodoro.applyPreset(minutes)
                    if Defaults[.enableHaptics] {
                        NSHapticFeedbackManager.defaultPerformer.perform(
                            .alignment,
                            performanceTime: .now
                        )
                    }
                } label: {
                    Text("\(minutes) min")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(
                            pomodoro.durationMinutes == minutes ? .white : Color(white: 0.75)
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            pomodoro.durationMinutes == minutes
                                ? Color.effectiveAccentBackground
                                : Color(nsColor: .secondarySystemFill).opacity(0.5)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Controls

    private var controlButtons: some View {
        VStack(spacing: 8) {
            HoverButton(
                icon: pomodoro.isRunning ? "pause.fill" : "play.fill",
                scale: .large
            ) {
                pomodoro.togglePlayPause()
            }

            HoverButton(icon: "arrow.counterclockwise", scale: .medium) {
                pomodoro.reset()
            }
        }
        .frame(width: 48)
    }
}

// MARK: - Duration wheel

private struct DurationWheelPicker: View {
    @Binding var selectedMinutes: Int
    let isEnabled: Bool

    @State private var scrollIndex: Int?
    @State private var isScrollingFromSelection = false

    private let itemHeight: CGFloat = 32
    private let visibleCount = 3
    private var edgeInset: Int { (visibleCount - 1) / 2 }

    private var minuteValues: [Int] {
        Array(PomodoroManager.minuteRange)
    }

    private var totalItemCount: Int {
        minuteValues.count + (edgeInset * 2)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .secondarySystemFill).opacity(0.35))

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.effectiveAccentBackground.opacity(0.55))
                .frame(height: itemHeight)
                .padding(.horizontal, 4)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<totalItemCount, id: \.self) { index in
                        if let minute = minute(at: index) {
                            Text("\(minute)")
                                .font(.system(
                                    size: 16,
                                    weight: selectedMinutes == minute ? .semibold : .regular,
                                    design: .rounded
                                ))
                                .monospacedDigit()
                                .foregroundStyle(selectedMinutes == minute ? .white : Color(white: 0.55))
                                .frame(height: itemHeight)
                                .frame(maxWidth: .infinity)
                                .id(index)
                        } else {
                            Color.clear
                                .frame(height: itemHeight)
                                .id(index)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollIndex, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .scrollDisabled(!isEnabled)
            .frame(height: itemHeight * CGFloat(visibleCount))
            .mask(
                LinearGradient(
                    colors: [.clear, .black, .black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .trailing) {
                Text("min")
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.55))
                    .padding(.trailing, 8)
            }
        }
        .onChange(of: scrollIndex) { _, newIndex in
            guard !isScrollingFromSelection else { return }
            guard let index = newIndex, let minute = minute(at: index), minute != selectedMinutes else {
                return
            }
            selectedMinutes = minute
            if Defaults[.enableHaptics] {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        .onChange(of: selectedMinutes) { _, newValue in
            scrollToMinute(newValue, animated: true)
        }
        .onAppear {
            scrollToMinute(selectedMinutes, animated: false)
        }
    }

    private func minute(at index: Int) -> Int? {
        let minuteIndex = index - edgeInset
        guard minuteIndex >= 0, minuteIndex < minuteValues.count else { return nil }
        return minuteValues[minuteIndex]
    }

    private func index(for minute: Int) -> Int? {
        guard let minuteIndex = minuteValues.firstIndex(of: minute) else { return nil }
        return minuteIndex + edgeInset
    }

    private func scrollToMinute(_ minute: Int, animated: Bool) {
        guard let targetIndex = index(for: minute) else { return }
        guard scrollIndex != targetIndex else { return }

        isScrollingFromSelection = true
        if animated {
            withAnimation(.smooth) {
                scrollIndex = targetIndex
            }
        } else {
            scrollIndex = targetIndex
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            isScrollingFromSelection = false
        }
    }
}

#Preview {
    PomodoroView()
        .frame(width: 640, height: 140)
        .background(.black)
}
