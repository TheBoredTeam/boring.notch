//
//  PomodoroSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct PomodoroSettings: View {
    @ObservedObject private var pomodoro = PomodoroTimerViewModel.shared

    @Default(.pomodoroFocusMinutes) var focusMinutes
    @Default(.pomodoroShortBreakMinutes) var shortBreakMinutes
    @Default(.pomodoroLongBreakMinutes) var longBreakMinutes
    @Default(.pomodoroLongBreakEvery) var longBreakEvery
    @Default(.pomodoroPhaseAlertMode) var phaseAlertMode
    @Default(.enableHaptics) var enableHaptics
    @Default(.showPomodoroPanel) private var showPomodoroPanel

    private var settingsLocked: Bool { pomodoro.isRunning }

    var body: some View {
        Form {
            if settingsLocked {
                Section {
                    Text(NSLocalizedString(
                        "pomodoro_settings_pause_first",
                        comment: "User must pause running timer before editing settings"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Button(NSLocalizedString("pomodoro_settings_pause_button", comment: "")) {
                        pomodoro.pause()
                    }
                }
            }

            Section {
                Defaults.Toggle(key: .showPomodoroPanel) {
                    Text(NSLocalizedString("pomodoro_show_panel", comment: "Show Pomodoro notch tab"))
                }
                .onChange(of: showPomodoroPanel) { _, enabled in
                    if !enabled {
                        BoringViewCoordinator.shared.showPomodoroInHome = false
                        if BoringViewCoordinator.shared.currentView == .pomodoro {
                            BoringViewCoordinator.shared.currentView = .home
                        }
                    }
                }
                Defaults.Toggle(key: .showPomodoroInClosedNotch) {
                    Text(NSLocalizedString("pomodoro_settings_show_timer_in_closed_notch", comment: "Show timer in closed notch"))
                }
            } header: {
                Text(NSLocalizedString("pomodoro_settings_visibility_header", comment: "Pomodoro settings: Visibility"))
            } footer: {
                Text(NSLocalizedString(
                    "pomodoro_settings_visibility_footer",
                    comment: "Footer: panel tab and closed notch"
                ))
            }
            .disabled(settingsLocked)

            Section {
                Stepper(value: $focusMinutes, in: 1...120) {
                    durationRow(
                        title: NSLocalizedString("pomodoro_focus_duration_title", comment: "Pomodoro: Focus duration"),
                        minutes: focusMinutes
                    )
                }
                Stepper(value: $shortBreakMinutes, in: 1...60) {
                    durationRow(
                        title: NSLocalizedString("pomodoro_short_break_title", comment: "Pomodoro: Short break"),
                        minutes: shortBreakMinutes
                    )
                }
                Stepper(value: $longBreakMinutes, in: 1...60) {
                    durationRow(
                        title: NSLocalizedString("pomodoro_long_break_title", comment: "Pomodoro: Long break"),
                        minutes: longBreakMinutes
                    )
                }
                Stepper(value: $longBreakEvery, in: 1...12) {
                    HStack {
                        Text(NSLocalizedString("pomodoro_long_break_every_label", comment: "Long break every"))
                        Spacer()
                        Text(String(format: NSLocalizedString("pomodoro_sessions_format", comment: "Number of sessions before a long break"), longBreakEvery))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(NSLocalizedString("pomodoro_settings_durations_header", comment: "Pomodoro settings: Durations"))
            }
            .disabled(settingsLocked)

            Section {
                Defaults.Toggle(key: .pomodoroAutoStartBreaks) {
                    Text(NSLocalizedString("pomodoro_auto_start_breaks_label", comment: "Auto-start breaks"))
                }
                Defaults.Toggle(key: .pomodoroAutoStartFocus) {
                    Text(NSLocalizedString("pomodoro_auto_start_focus_sessions_label", comment: "Auto-start focus sessions"))
                }
            } header: {
                Text(NSLocalizedString("pomodoro_settings_automation_header", comment: "Pomodoro settings: Automation"))
            }
            .disabled(settingsLocked)

            Section {
                Picker(
                    NSLocalizedString("pomodoro_phase_alerts_picker", comment: "Picker label"),
                    selection: $phaseAlertMode
                ) {
                    ForEach(PomodoroPhaseAlertMode.allCases) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                }
                Defaults.Toggle(key: .pomodoroSoundOnPhaseComplete) {
                    Text(NSLocalizedString("pomodoro_sound_on_phase_complete_label", comment: "Play sound on phase completion"))
                }
            } header: {
                Text(NSLocalizedString("pomodoro_alerts_section", comment: ""))
            } footer: {
                Text(NSLocalizedString("pomodoro_alerts_footer", comment: ""))
            }
            .disabled(settingsLocked)

            Section {
                Defaults.Toggle(key: .pomodoroHapticPhaseComplete) {
                    Text(NSLocalizedString("pomodoro_haptic_phase", comment: ""))
                }
                .disabled(!enableHaptics)
                Defaults.Toggle(key: .pomodoroHapticCountdown) {
                    Text(NSLocalizedString("pomodoro_haptic_countdown", comment: ""))
                }
                .disabled(!enableHaptics)
            } header: {
                Text(NSLocalizedString("pomodoro_haptics_section", comment: ""))
            } footer: {
                if !enableHaptics {
                    Text(NSLocalizedString("pomodoro_haptics_need_global", comment: ""))
                }
            }
            .disabled(settingsLocked)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Pomodoro")
        .onChange(of: focusMinutes) { _, _ in
            if !settingsLocked { pomodoro.clampRemainingToPhaseDuration() }
        }
        .onChange(of: shortBreakMinutes) { _, _ in
            if !settingsLocked { pomodoro.clampRemainingToPhaseDuration() }
        }
        .onChange(of: longBreakMinutes) { _, _ in
            if !settingsLocked { pomodoro.clampRemainingToPhaseDuration() }
        }
    }

    @ViewBuilder
    private func durationRow(title: String, minutes: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(String(format: NSLocalizedString("pomodoro_minutes_format", comment: "Minutes (e.g., 5 min)"), minutes))
                .foregroundStyle(.secondary)
        }
    }
}
