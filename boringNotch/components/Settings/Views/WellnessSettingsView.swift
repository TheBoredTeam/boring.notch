//
//  WellnessSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import SwiftUI

struct WellnessSettings: View {
    @Default(.eyeBreakEnabled) var eyeBreakEnabled
    @Default(.eyeBreakIntervalMinutes) var eyeBreakIntervalMinutes
    @Default(.eyeBreakDurationSeconds) var eyeBreakDurationSeconds
    @Default(.eyeBreakSnoozeMinutes) var eyeBreakSnoozeMinutes
#if DEBUG
    @ObservedObject var eyeBreakReminder = EyeBreakReminderManager.shared
#endif

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .eyeBreakEnabled) {
                    Text("Enable eye-break reminders")
                }
            } footer: {
                Text("Uses the 20-20-20 rule to reduce eye strain: every 20 minutes, look 20 feet away for 20 seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $eyeBreakIntervalMinutes, in: 5...120, step: 1) {
                    HStack {
                        Text("Active interval")
                        Spacer()
                        Text("\(eyeBreakIntervalMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $eyeBreakDurationSeconds, in: 5...120, step: 1) {
                    HStack {
                        Text("Break countdown")
                        Spacer()
                        Text("\(eyeBreakDurationSeconds) sec")
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $eyeBreakSnoozeMinutes, in: 1...60, step: 1) {
                    HStack {
                        Text("Snooze duration")
                        Spacer()
                        Text("\(eyeBreakSnoozeMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                }

                Defaults.Toggle(key: .eyeBreakSoundEnabled) {
                    Text("Play sound for reminder and completion")
                }

                Defaults.Toggle(key: .eyeBreakPauseMediaOnPopup) {
                    Text("Pause media when reminder appears")
                }
            } header: {
                Text("Reminder settings")
            }
            .disabled(!eyeBreakEnabled)

#if DEBUG
            Section {
                HStack {
                    Text("Active timer")
                    Spacer()
                    Text(formattedDuration(eyeBreakReminder.debugState.activeSecondsAccumulated))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Counting time")
                    Spacer()
                    Text(eyeBreakReminder.debugState.isAccruingActiveTime ? "Yes" : "No")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Due pending")
                    Spacer()
                    Text(eyeBreakReminder.debugState.duePending ? "Yes" : "No")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button("Trigger now") {
                        eyeBreakReminder.debugTriggerReminderNow()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reset") {
                        eyeBreakReminder.debugResetState()
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Debug")
            } footer: {
                Text("Available only in DEBUG builds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
#endif
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Wellness")
    }

#if DEBUG
    private func formattedDuration(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let remaining = clamped % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remaining)
    }
#endif
}
