//
//  PomodoroSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct PomodoroSettingsView: View {
    @Default(.enablePomodoro) var enablePomodoro
    @Default(.pomodoroFocusMinutes) var focusMinutes
    @Default(.pomodoroShortBreakMinutes) var shortBreakMinutes
    @Default(.pomodoroLongBreakMinutes) var longBreakMinutes
    @Default(.pomodoroSessionsBeforeLongBreak) var sessionsBeforeLongBreak

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enablePomodoro) {
                    Text("Enable focus timer")
                }
                Defaults.Toggle(key: .pomodoroShowInClosedNotch) {
                    Text("Show countdown in closed notch")
                }
                .disabled(!enablePomodoro)
            } header: {
                Text("General")
            } footer: {
                Text(
                    "Adds a Timer tab to the open notch. A running timer sits in front of the music live activity; swipe to switch between them.",
                    comment: "Footer explaining where the focus timer appears."
                )
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            Section {
                Stepper(value: $focusMinutes, in: 1...120) {
                    Text("Focus: \(focusMinutes) min", comment: "Focus session length in minutes.")
                }
                Stepper(value: $shortBreakMinutes, in: 1...60) {
                    Text("Short break: \(shortBreakMinutes) min", comment: "Short break length in minutes.")
                }
                Stepper(value: $longBreakMinutes, in: 1...90) {
                    Text("Long break: \(longBreakMinutes) min", comment: "Long break length in minutes.")
                }
                Stepper(value: $sessionsBeforeLongBreak, in: 1...12) {
                    Text("Long break after \(sessionsBeforeLongBreak) sessions", comment: "Number of focus sessions before a long break.")
                }
            } header: {
                Text("Durations")
            }
            .disabled(!enablePomodoro)
            Section {
                Defaults.Toggle(key: .pomodoroAutoStartNext) {
                    Text("Automatically start the next phase")
                }
                Defaults.Toggle(key: .pomodoroPlaySound) {
                    Text("Play a sound when a phase ends")
                }
            } header: {
                Text("Behavior")
            }
            .disabled(!enablePomodoro)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Timer")
    }
}
