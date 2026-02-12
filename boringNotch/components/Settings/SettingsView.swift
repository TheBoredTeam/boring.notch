//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    @State private var selectedTab = "General"
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "General") {
                    Label("General", systemImage: "gear")
                }
                NavigationLink(value: "Appearance") {
                    Label("Appearance", systemImage: "eye")
                }
                NavigationLink(value: "Media") {
                    Label("Media", systemImage: "play.laptopcomputer")
                }
                NavigationLink(value: "Calendar") {
                    Label("Calendar", systemImage: "calendar")
                }
                NavigationLink(value: "HUD") {
                    Label("HUDs", systemImage: "dial.medium.fill")
                }
                NavigationLink(value: "Battery") {
                    Label("Battery", systemImage: "battery.100.bolt")
                }
                NavigationLink(value: "Wellness") {
                    Label("Wellness", systemImage: "eye")
                }
                NavigationLink(value: "Shelf") {
                    Label("Shelf", systemImage: "books.vertical")
                }
                NavigationLink(value: "Shortcuts") {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                NavigationLink(value: "Advanced") {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                NavigationLink(value: "About") {
                    Label("About", systemImage: "info.circle")
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case "General":
                    GeneralSettings()
                case "Appearance":
                    Appearance()
                case "Media":
                    Media()
                case "Calendar":
                    CalendarSettings()
                case "HUD":
                    HUD()
                case "Battery":
                    Charge()
                case "Wellness":
                    WellnessSettings()
                case "Shelf":
                    Shelf()
                case "Shortcuts":
                    Shortcuts()
                case "Advanced":
                    Advanced()
                case "About":
                    if let controller = updaterController {
                        About(updaterController: controller)
                    } else {
                        // Fallback with a default controller
                        About(
                            updaterController: SPUStandardUpdaterController(
                                startingUpdater: false, updaterDelegate: nil,
                                userDriverDelegate: nil))
                    }
                default:
                    GeneralSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: .accentColorChanged)) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }
}

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
