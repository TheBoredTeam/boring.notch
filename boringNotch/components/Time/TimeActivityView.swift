//
//  TimeActivityView.swift
//  boringNotch
//
//  Timer and stopwatch interaction inspired by Cris2907/not-so-boring-notch.
//

import Defaults
import SwiftUI

struct TimeActivityView: View {
    @ObservedObject private var manager = TimeActivityManager.shared
    @Default(.timerDefaultMinutes) private var defaultTimerMinutes
    @Default(.stopwatchShowCentiseconds) private var stopwatchShowCentiseconds

    @State private var selectedKind: TimeActivityKind = .timer
    @State private var selectedMinutes = Defaults[.timerDefaultMinutes]

    private let minuteRange = 1...120
    private let presets = [5, 10, 15, 25, 30, 60]

    var body: some View {
        Group {
            if let snapshot = manager.snapshot {
                activeSession(snapshot)
            } else {
                setupView
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timer and stopwatch controls")
        .onAppear {
            guard manager.snapshot == nil else { return }
            selectedMinutes = clamped(defaultTimerMinutes)
        }
        .onChange(of: defaultTimerMinutes) { _, newValue in
            guard manager.snapshot == nil else { return }
            selectedMinutes = clamped(newValue)
        }
    }

    private var setupView: some View {
        VStack(spacing: 9) {
            Picker("Time activity", selection: $selectedKind) {
                Text("Timer").tag(TimeActivityKind.timer)
                Text("Stopwatch").tag(TimeActivityKind.stopwatch)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(.orange)
            .controlSize(.small)
            .frame(width: 210)

            if selectedKind == .timer {
                timerSetup
            } else {
                idleStopwatch
            }
        }
    }

    private var timerSetup: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                minuteButton(systemImage: "minus") {
                    selectedMinutes = max(minuteRange.lowerBound, selectedMinutes - 1)
                }
                .disabled(selectedMinutes == minuteRange.lowerBound)

                Text(TimeActivityFormatter.timer(TimeInterval(selectedMinutes * 60)))
                    .font(.system(size: 42, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
                    .frame(minWidth: 130)
                    .accessibilityLabel("Timer duration \(selectedMinutes) minutes")

                minuteButton(systemImage: "plus") {
                    selectedMinutes = min(minuteRange.upperBound, selectedMinutes + 1)
                }
                .disabled(selectedMinutes == minuteRange.upperBound)
            }

            HStack(spacing: 7) {
                ForEach(presets, id: \.self) { minutes in
                    Button("\(minutes) min") {
                        withAnimation(.snappy(duration: 0.18)) {
                            selectedMinutes = minutes
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(selectedMinutes == minutes ? .orange : .secondary)
                }

                Spacer(minLength: 8)

                Button {
                    manager.startTimer(duration: TimeInterval(selectedMinutes * 60))
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(.orange.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start \(selectedMinutes) minute timer")
            }
        }
    }

    private var idleStopwatch: some View {
        sessionLayout(
            label: "Stopwatch",
            time: stopwatchShowCentiseconds ? "00:00.00" : "00:00",
            primaryIcon: "play.fill",
            primaryLabel: "Start stopwatch",
            primaryAction: { manager.startStopwatch() },
            secondaryIcon: nil,
            secondaryLabel: nil,
            secondaryAction: nil,
            isFinished: false
        )
    }

    private func activeSession(_ snapshot: TimeActivitySnapshot) -> some View {
        TimelineView(.animation(minimumInterval: updateInterval(for: snapshot))) { timeline in
            sessionLayout(
                label: snapshot.kind == .timer ? "Timer" : "Stopwatch",
                time: displayText(for: snapshot, at: timeline.date),
                primaryIcon: snapshot.phase == .finished
                    ? "checkmark"
                    : (snapshot.phase == .running ? "pause.fill" : "play.fill"),
                primaryLabel: snapshot.phase == .finished
                    ? "Dismiss timer"
                    : (snapshot.phase == .running ? "Pause" : "Resume"),
                primaryAction: {
                    if snapshot.phase == .finished {
                        manager.dismissCompletion()
                    } else if snapshot.phase == .running {
                        manager.pause()
                    } else {
                        manager.resume()
                    }
                },
                secondaryIcon: snapshot.phase == .finished
                    ? nil
                    : (snapshot.kind == .timer ? "xmark" : "arrow.counterclockwise"),
                secondaryLabel: snapshot.phase == .finished
                    ? nil
                    : (snapshot.kind == .timer ? "Cancel" : "Reset"),
                secondaryAction: snapshot.phase == .finished ? nil : { manager.reset() },
                isFinished: snapshot.phase == .finished
            )
        }
    }

    private func sessionLayout(
        label: LocalizedStringKey,
        time: String,
        primaryIcon: String,
        primaryLabel: LocalizedStringKey,
        primaryAction: @escaping () -> Void,
        secondaryIcon: String?,
        secondaryLabel: LocalizedStringKey?,
        secondaryAction: (() -> Void)?,
        isFinished: Bool
    ) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isFinished ? LocalizedStringKey("Timer Done") : label)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.9))

                Text(time)
                    .font(.system(size: 46, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 12)

            sessionButton(
                systemImage: primaryIcon,
                accessibilityLabel: primaryLabel,
                isPrimary: true,
                action: primaryAction
            )

            if let secondaryIcon,
               let secondaryLabel,
               let secondaryAction {
                sessionButton(
                    systemImage: secondaryIcon,
                    accessibilityLabel: secondaryLabel,
                    isPrimary: false,
                    action: secondaryAction
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func minuteButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func sessionButton(
        systemImage: String,
        accessibilityLabel: LocalizedStringKey,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(isPrimary ? .orange.opacity(0.24) : .white.opacity(0.14))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isPrimary ? .orange : .white)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func clamped(_ minutes: Int) -> Int {
        min(max(minutes, minuteRange.lowerBound), minuteRange.upperBound)
    }

    private func updateInterval(for snapshot: TimeActivitySnapshot) -> TimeInterval? {
        guard snapshot.phase == .running else { return nil }
        return snapshot.kind == .stopwatch && stopwatchShowCentiseconds ? 0.03 : 0.25
    }

    private func displayText(for snapshot: TimeActivitySnapshot, at date: Date) -> String {
        if snapshot.phase == .finished { return String(localized: "Done") }
        if snapshot.kind == .timer {
            return TimeActivityFormatter.timer(snapshot.remaining(at: date))
        }
        return TimeActivityFormatter.stopwatch(
            snapshot.elapsed(at: date),
            includesCentiseconds: stopwatchShowCentiseconds
        )
    }
}

struct ClosedTimeActivityView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var manager = TimeActivityManager.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: updateInterval)) { timeline in
            if let snapshot = manager.snapshot {
                HStack(spacing: 0) {
                    HStack(spacing: 7) {
                        Image(systemName: snapshot.kind == .timer ? "timer" : "stopwatch.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(displayText(for: snapshot, at: timeline.date))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(.orange)
                    .frame(width: 120)

                    Rectangle()
                        .fill(.black)
                        .frame(width: vm.closedNotchSize.width + 10)

                    Text(statusText(for: snapshot))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(snapshot.phase == .finished ? .orange : .secondary)
                        .frame(width: 70)
                }
                .frame(height: vm.effectiveClosedNotchHeight)
                .background(alignment: .leading) {
                    LinearGradient(
                        colors: [.orange.opacity(0.18), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .blur(radius: 12)
                }
            }
        }
    }

    private var updateInterval: TimeInterval? {
        guard let snapshot = manager.snapshot, snapshot.phase == .running else { return nil }
        return snapshot.kind == .stopwatch ? 0.1 : 0.25
    }

    private func displayText(for snapshot: TimeActivitySnapshot, at date: Date) -> String {
        if snapshot.phase == .finished { return String(localized: "Done") }
        if snapshot.kind == .timer {
            return TimeActivityFormatter.timer(snapshot.remaining(at: date))
        }
        return TimeActivityFormatter.stopwatch(snapshot.elapsed(at: date), includesCentiseconds: false)
    }

    private func statusText(for snapshot: TimeActivitySnapshot) -> LocalizedStringKey {
        if snapshot.phase == .finished { return "Finished" }
        if snapshot.phase == .paused { return "Paused" }
        return snapshot.kind == .timer ? "Timer" : "Stopwatch"
    }
}

#Preview {
    TimeActivityView()
        .frame(width: 600, height: 140)
        .background(.black)
}
