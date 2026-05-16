//
//  FocusEnforcerView.swift
//  boringNotch
//

import Defaults
import KeyboardShortcuts
import SwiftUI

private let focusDurations: [Int] = [5, 10, 15, 25]

struct FocusEnforcerView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var manager = FocusEnforcerManager.shared

    @State private var taskInput: String = ""
    @Default(.focusDefaultDuration) private var defaultDuration: Int
    @State private var selectedDuration: Int = Defaults[.focusDefaultDuration]
    @FocusState private var inputFocused: Bool

    var body: some View {
        Group {
            if let session = manager.session {
                if manager.isFinished {
                    finishedState(session: session)
                } else {
                    activeState(session: session)
                }
            } else {
                idleState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .animation(.smooth, value: manager.session != nil)
        .animation(.smooth, value: manager.isFinished)
    }

    // MARK: - Idle

    private var idleState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("What are you working on?")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
            }

            TextField("e.g. Fix login bug", text: $taskInput)
                .textFieldStyle(.plain)
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(.white)
                .focused($inputFocused)
                .onSubmit(startSession)

            HStack(spacing: 6) {
                ForEach(focusDurations, id: \.self) { mins in
                    durationChip(mins: mins)
                }
                Spacer()
                Button(action: startSession) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Go")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(canStart ? Color.accentColor : Color.gray.opacity(0.4))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
            }
        }
        .padding(.horizontal, 4)
        .onAppear {
            selectedDuration = defaultDuration
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                inputFocused = true
            }
        }
    }

    private var canStart: Bool {
        !taskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func durationChip(mins: Int) -> some View {
        Button {
            selectedDuration = mins
        } label: {
            Text("\(mins)m")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(selectedDuration == mins ? .white : .gray)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(selectedDuration == mins
                              ? Color.accentColor.opacity(0.85)
                              : Color(nsColor: .secondarySystemFill))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Active

    private func activeState(session: FocusSession) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0, 1 - manager.progress))
                    .stroke(Color.accentColor,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.0), value: manager.progress)
                Text(formatTime(manager.remaining))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 8) {
                Text(session.taskName)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    actionButton(label: "Done", icon: "checkmark", tint: .green) {
                        manager.stop()
                        vm.close()
                    }
                    actionButton(label: "+2m", icon: nil, tint: Color(nsColor: .secondarySystemFill)) {
                        manager.extend(by: 120)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Finished

    private func finishedState(session: FocusSession) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: manager.isFinished)
            Text("Done!")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
            Text(session.taskName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 8) {
                actionButton(label: "Finish", icon: "checkmark", tint: .green) {
                    manager.stop()
                    vm.close()
                }
                actionButton(label: "+2 min", icon: "plus", tint: Color(nsColor: .secondarySystemFill)) {
                    manager.extend(by: 120)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func actionButton(label: String, icon: String?, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                }
                Text(label)
            }
            .font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.85)))
        }
        .buttonStyle(.plain)
    }

    private func startSession() {
        guard canStart else { return }
        let trimmed = taskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        manager.start(task: trimmed, duration: TimeInterval(selectedDuration * 60))
        taskInput = ""
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            vm.close()
        }
    }
}

// MARK: - Closed-notch chin indicator

struct FocusInlineView: View {
    @ObservedObject var manager = FocusEnforcerManager.shared
    @EnvironmentObject var vm: BoringViewModel

    private static let maxTaskNameLength = 32

    private func trimmed(_ name: String) -> String {
        guard name.count > Self.maxTaskNameLength else { return name }
        return String(name.prefix(Self.maxTaskNameLength)) + "…"
    }

    var body: some View {
        if let session = manager.session {
            HStack(spacing: 0) {
                // Left side — natural width
                HStack(spacing: 6) {
                    Image(systemName: manager.isFinished ? "checkmark.circle.fill" : "hourglass")
                        .foregroundStyle(manager.isFinished ? Color.green : Color.accentColor)
                        .font(.system(size: 11, weight: .semibold))
                        .symbolEffect(.pulse, isActive: manager.isFinished)
                    Text(trimmed(session.taskName))
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .fixedSize()

                // Center gap behind the actual notch silhouette
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width + 12)

                // Right side — natural width
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: max(0, 1 - manager.progress))
                            .stroke(manager.isFinished ? Color.green : Color.accentColor,
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1.0), value: manager.progress)
                    }
                    .frame(width: 14, height: 14)

                    Text(formatTime(manager.remaining))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .fixedSize()
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - Time formatting

func formatTime(_ interval: TimeInterval) -> String {
    let total = Int(ceil(max(0, interval)))
    let minutes = total / 60
    let seconds = total % 60
    return String(format: "%d:%02d", minutes, seconds)
}

// MARK: - Settings

struct FocusSettings: View {
    @Default(.focusDefaultDuration) var focusDefaultDuration: Int

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .focusEnforcerEnabled) {
                    Text("Enable Focus")
                }
            } header: {
                Text("General")
            } footer: {
                Text("Focus is a brutally simple timer for one task at a time. Use the keyboard shortcut to start a session from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Default duration", selection: $focusDefaultDuration) {
                    ForEach(focusDurations, id: \.self) { mins in
                        Text("\(mins) minutes").tag(mins)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Defaults")
            }

            Section {
                KeyboardShortcuts.Recorder("Start focus session:", name: .startFocusSession)
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Press this shortcut to open the notch directly on the Focus tab from any app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Focus")
    }
}
