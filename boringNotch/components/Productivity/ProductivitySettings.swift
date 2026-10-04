//
//  ProductivitySettings.swift
//  boringNotch
//
//  Settings pane for the clipboard, timer, notes, and to-do tabs.
//

import Defaults
import SwiftUI

struct ProductivitySettings: View {
    @Default(.clipboardHistoryLimit) var clipboardHistoryLimit
    @Default(.focusDurationMinutes) var focusDurationMinutes
    @Default(.shortBreakDurationMinutes) var shortBreakDurationMinutes
    @Default(.longBreakDurationMinutes) var longBreakDurationMinutes
    @Default(.sessionsBeforeLongBreak) var sessionsBeforeLongBreak
    @ObservedObject var clipboard = ClipboardManager.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showClipboardTab) {
                    Text("Enable clipboard history")
                }
                Stepper(value: $clipboardHistoryLimit, in: 10...200, step: 10) {
                    Text("Keep the last \(clipboardHistoryLimit) clips")
                }
                Defaults.Toggle(key: .clipboardIgnorePasswordManagers) {
                    Text("Ignore clips copied from password managers")
                }
                Button("Clear clipboard history", role: .destructive) {
                    clipboard.clearAll()
                }
                .disabled(clipboard.items.isEmpty)
            } header: {
                Text("Clipboard")
            } footer: {
                Text("History stays on this Mac. Items that apps mark as concealed or temporary (such as passwords) are never saved, and images are kept only until boringNotch quits.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .showTimerTab) {
                    Text("Enable focus timer")
                }
                Stepper(value: $focusDurationMinutes, in: 1...180) {
                    Text("Focus: \(focusDurationMinutes) min")
                }
                Stepper(value: $shortBreakDurationMinutes, in: 1...60) {
                    Text("Short break: \(shortBreakDurationMinutes) min")
                }
                Stepper(value: $longBreakDurationMinutes, in: 1...90) {
                    Text("Long break: \(longBreakDurationMinutes) min")
                }
                Stepper(value: $sessionsBeforeLongBreak, in: 1...10) {
                    Text("Long break after \(sessionsBeforeLongBreak) focus sessions")
                }
                Defaults.Toggle(key: .showTimerLiveActivity) {
                    Text("Show countdown in the closed notch")
                }
                Defaults.Toggle(key: .playTimerFinishedSound) {
                    Text("Play a sound when a session ends")
                }
            } header: {
                Text("Timer")
            }

            Section {
                Defaults.Toggle(key: .showNotesTab) {
                    Text("Enable quick note")
                }
                Defaults.Toggle(key: .showTodosTab) {
                    Text("Enable to-do list")
                }
            } header: {
                Text("Notes & To-Dos")
            } footer: {
                Text("New tabs appear in the open notch. Turn on \"Always show tabs\" in Appearance to see them even when the shelf is empty.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Productivity")
    }
}
