//
//  FocusSettings.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct FocusSettings: View {
    @Default(.pomodoroWorkDuration) var workDuration
    @Default(.pomodoroShortBreakDuration) var shortBreak
    @Default(.pomodoroLongBreakDuration) var longBreak
    @Default(.pomodoroCyclesBeforeLongBreak) var cycles
    @Default(.pomodoroAutoDND) var autoDND

    @ObservedObject private var pomodoro = PomodoroManager.shared

    var body: some View {
        Form {
            Section {
                durationStepper("Focus session", value: $workDuration, range: 1...120, unit: "min")
                durationStepper("Short break", value: $shortBreak, range: 1...60, unit: "min")
                durationStepper("Long break", value: $longBreak, range: 1...60, unit: "min")
                Stepper(value: $cycles, in: 1...12) {
                    HStack {
                        Text("Sessions before long break")
                        Spacer()
                        Text("\(cycles)").foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Timer")
            }

            Section {
                Defaults.Toggle(key: .pomodoroAutoDND) {
                    Text("Enable Do Not Disturb during focus")
                }
            } header: {
                Text("Do Not Disturb")
            } footer: {
                if autoDND {
                    Text("Requires two macOS Shortcuts. Open the Shortcuts app and create:\n• \"BoringNotch Focus On\" → Set Focus → Do Not Disturb → On\n• \"BoringNotch Focus Off\" → Set Focus → turn Off\nThey run automatically when a focus session starts and ends.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                HStack {
                    statTile(title: "Today", value: focusTimeString(pomodoro.todayFocusSeconds), sub: "\(pomodoro.todayPomodoros) sessions")
                    Divider().frame(height: 32)
                    statTile(title: "This week", value: focusTimeString(pomodoro.weekFocusSeconds()), sub: "\(pomodoro.weekPomodoros()) sessions")
                }
                Button(role: .destructive) {
                    pomodoro.resetStats()
                } label: {
                    Text("Reset statistics")
                }
            } header: {
                Text("Statistics")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Focus")
    }

    private func durationStepper(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        Stepper(value: value, in: range, step: 1) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)").foregroundColor(.secondary)
            }
        }
    }

    private func statTile(title: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title3).fontWeight(.semibold)
            Text(sub).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func focusTimeString(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
