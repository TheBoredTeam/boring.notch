//
//  PomodoroSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct PomodoroSettingsView: View {
    @Default(.pomodoroWorkDuration) var workDuration
    @Default(.pomodoroShortBreakDuration) var shortBreakDuration
    @Default(.pomodoroLongBreakDuration) var longBreakDuration
    @Default(.pomodoroLongBreakInterval) var longBreakInterval
    @Default(.pomodoroWorkName) var workName
    @Default(.pomodoroShortBreakName) var shortBreakName
    @Default(.pomodoroLongBreakName) var longBreakName
    @Default(.pomodoroTargetSessions) var targetSessions
    @Default(.pomodoroSoundName) var soundName
    @Default(.pomodoroAutoStartBreaks) var autoStartBreaks
    @Default(.pomodoroAutoStartWork) var autoStartWork
    @Default(.pomodoroSoundEnabled) var soundEnabled

    let availableSounds = ["Glass", "Basso", "Blow", "Bottle", "Frog", "Hero", "Morse", "Ping", "Pop", "Tink"]

    private var currentPresetName: String {
        let w = Int(workDuration / 60)
        let s = Int(shortBreakDuration / 60)
        let l = Int(longBreakDuration / 60)

        if w == 25 && s == 5 && l == 15 { return "Classic" }
        if w == 50 && s == 10 && l == 20 { return "Extended" }
        if w == 90 && s == 15 && l == 30 { return "DeepWork" }
        if w == 15 && s == 3 && l == 10 { return "Sprint" }
        return "Custom"
    }

    private func applyPresetByName(_ name: String) {
        switch name {
        case "Classic":
            applyPreset(w: 25, s: 5, l: 15)
        case "Extended":
            applyPreset(w: 50, s: 10, l: 20)
        case "DeepWork":
            applyPreset(w: 90, s: 15, l: 30)
        case "Sprint":
            applyPreset(w: 15, s: 3, l: 10)
        default:
            break
        }
    }

    private func applyPreset(w: Int, s: Int, l: Int) {
        workDuration = TimeInterval(w * 60)
        shortBreakDuration = TimeInterval(s * 60)
        longBreakDuration = TimeInterval(l * 60)
        PomodoroManager.shared.resetTimeToPhase()
    }

    var body: some View {
        Form {
            Section("Preset Workflows") {
                Picker("Preset Workflow", selection: Binding(
                    get: { currentPresetName },
                    set: { applyPresetByName($0) }
                )) {
                    Text("Custom").tag("Custom")
                    Text("Classic Pomodoro (25 / 5 / 15 min)").tag("Classic")
                    Text("Extended Focus (50 / 10 / 20 min)").tag("Extended")
                    Text("Deep Work (90 / 15 / 30 min)").tag("DeepWork")
                    Text("Quick Sprint (15 / 3 / 10 min)").tag("Sprint")
                }
                .tint(.effectiveAccent)
            }

            Section("Custom Phase Labels") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Work:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .leading)
                        TextField("", text: $workName, prompt: Text("Work Phase Name"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Short Break:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .leading)
                        TextField("", text: $shortBreakName, prompt: Text("Short Break Name"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Long Break:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .leading)
                        TextField("", text: $longBreakName, prompt: Text("Long Break Name"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Spacer()
                        Button("Save") {
                            PomodoroManager.shared.objectWillChange.send()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.effectiveAccent)
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }

            Section("Durations & Goals") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Work Duration:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 145, alignment: .leading)
                        TextField("", value: Binding(
                            get: { Int(workDuration / 60) },
                            set: { workDuration = TimeInterval(max(1, min(180, $0)) * 60) }
                        ), formatter: NumberFormatter())
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        Text("min")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Short Break Duration:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 145, alignment: .leading)
                        TextField("", value: Binding(
                            get: { Int(shortBreakDuration / 60) },
                            set: { shortBreakDuration = TimeInterval(max(1, min(60, $0)) * 60) }
                        ), formatter: NumberFormatter())
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        Text("min")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Long Break Duration:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 145, alignment: .leading)
                        TextField("", value: Binding(
                            get: { Int(longBreakDuration / 60) },
                            set: { longBreakDuration = TimeInterval(max(1, min(120, $0)) * 60) }
                        ), formatter: NumberFormatter())
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        Text("min")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Long Break Interval:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 145, alignment: .leading)
                        TextField("", value: $longBreakInterval, formatter: NumberFormatter())
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("sessions")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Daily Target Goal:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 145, alignment: .leading)
                        TextField("", value: $targetSessions, formatter: NumberFormatter())
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("sessions")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Spacer()
                        Button("Save") {
                            PomodoroManager.shared.resetTimeToPhase()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.effectiveAccent)
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }

            Section("Notifications & Audio Alert") {
                Toggle("Play Completion Sound", isOn: $soundEnabled)
                    .tint(.effectiveAccent)

                if soundEnabled {
                    Picker("Chime Sound", selection: $soundName) {
                        ForEach(availableSounds, id: \.self) { sound in
                            Text(sound).tag(sound)
                        }
                    }

                    Button("Preview Chime Sound") {
                        NSSound(named: NSSound.Name(soundName))?.play()
                    }
                }

                Toggle("Auto-start Breaks", isOn: $autoStartBreaks)
                    .tint(.effectiveAccent)
                Toggle("Auto-start Work Sessions", isOn: $autoStartWork)
                    .tint(.effectiveAccent)
            }

            Section {
                Button("Reset All Preferences to Defaults") {
                    workDuration = 25 * 60
                    shortBreakDuration = 5 * 60
                    longBreakDuration = 15 * 60
                    longBreakInterval = 4
                    workName = "Work"
                    shortBreakName = "Short Break"
                    longBreakName = "Long Break"
                    targetSessions = 8
                    soundName = "Glass"
                    autoStartBreaks = false
                    autoStartWork = false
                    soundEnabled = true
                    PomodoroManager.shared.reset()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }
}
