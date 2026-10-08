//
//  PomodoroSettings.swift
//  boringNotch
//
//  Settings pane for the Pomodoro timer.
//

import Defaults
import SwiftUI

struct PomodoroSettings: View {
    @Default(.enablePomodoro) var enablePomodoro
    @Default(.pomodoroFocusMinutes) var focusMinutes
    @Default(.pomodoroShortBreakMinutes) var shortBreakMinutes
    @Default(.pomodoroLongBreakMinutes) var longBreakMinutes
    @Default(.pomodoroSessionsBeforeLongBreak) var sessionsBeforeLongBreak

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enablePomodoro) {
                    Text("Enable Pomodoro timer")
                }
                Defaults.Toggle(key: .pomodoroShowInClosedNotch) {
                    Text("Show countdown in the closed notch")
                }
                .disabled(!enablePomodoro)
            } header: {
                Text("General")
            }

            Section {
                minutesStepper("Focus", value: $focusMinutes, range: 1...180)
                minutesStepper("Short break", value: $shortBreakMinutes, range: 1...60)
                minutesStepper("Long break", value: $longBreakMinutes, range: 1...90)
                Stepper(value: $sessionsBeforeLongBreak, in: 2...10) {
                    HStack {
                        Text("Focus sessions before a long break")
                        Spacer()
                        Text("\(sessionsBeforeLongBreak)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Durations")
            } footer: {
                Text("Changes apply to the next phase that starts. A phase already in progress keeps its length.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .disabled(!enablePomodoro)

            Section {
                Defaults.Toggle(key: .pomodoroAutoStartNext) {
                    Text("Start the next phase automatically")
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
        .navigationTitle("Pomodoro")
    }

    private func minutesStepper(_ title: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue) min")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    PomodoroSettings()
}
