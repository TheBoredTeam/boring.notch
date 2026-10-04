//
//  FocusSettings.swift
//  boringNotch
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct FocusSettings: View {
    @Default(.pomodoroWorkDuration) var workDuration
    @Default(.pomodoroShortBreakDuration) var shortBreak
    @Default(.pomodoroLongBreakDuration) var longBreak
    @Default(.pomodoroCyclesBeforeLongBreak) var cycles
    @Default(.pomodoroAutoDND) var autoDND
    @Default(.pomodoroCompletionSound) var chimeEnabled
    @Default(.pomodoroChimeSound) var chimeSound
    @Default(.pomodoroChimeCount) var chimeCount
    @Default(.pomodoroCustomChimePath) var customChimePath
    @Default(.reelsBlockerEnabled) var reelsEnabled
    @Default(.reelsDailyLimitMinutes) var reelsLimit
    @Default(.reelsNotchMetric) var reelsNotchMetric

    @ObservedObject private var pomodoro = PomodoroManager.shared
    @ObservedObject private var reels = ReelsManager.shared

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
                Defaults.Toggle(key: .pomodoroCompletionSound) {
                    Text("Play chime when a session ends")
                }

                if chimeEnabled {
                    Picker("Chime sound", selection: $chimeSound) {
                        ForEach(PomodoroManager.chimeOptions, id: \.self) { name in
                            Text(name == "Custom" ? "Custom file…" : name).tag(name)
                        }
                    }

                    if chimeSound == "Custom" {
                        HStack {
                            Text("Audio file")
                            Spacer()
                            Text(customChimePath.isEmpty
                                 ? "None selected"
                                 : (customChimePath as NSString).lastPathComponent)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose…") { chooseCustomChime() }
                        }
                    }

                    Picker("Repeat", selection: $chimeCount) {
                        Text("Once").tag(1)
                        Text("Twice").tag(2)
                        Text("3 times").tag(3)
                    }

                    Button {
                        pomodoro.playChime(times: chimeCount)
                    } label: {
                        Label("Preview chime", systemImage: "play.circle")
                    }
                }
            } header: {
                Text("Chime")
            } footer: {
                Text("Pick a built-in chime or your own audio file as a ringtone, and how many times it repeats. Use Preview to hear it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Defaults.Toggle(key: .pomodoroAutoStartNext) {
                    Text("Auto-start next session")
                }
                Defaults.Toggle(key: .pomodoroPreventSleep) {
                    Text("Keep Mac awake during sessions")
                }
            } header: {
                Text("Automation")
            } footer: {
                Text("Auto-start: when a session ends, the next one (break or focus) begins automatically.\nKeep awake: stops the Mac from idle-sleeping mid-session so the chime fires even if you step away (a physically closed lid will still sleep).")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

            reelsSection
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Focus")
    }

    // MARK: - Reels blocker

    @ViewBuilder
    private var reelsSection: some View {
        Section {
            Defaults.Toggle(key: .reelsBlockerEnabled) {
                Text("Track & limit reels")
            }

            if reelsEnabled {
                Defaults.Toggle(key: .reelsTrackInstagram) { Text("Instagram Reels") }
                Defaults.Toggle(key: .reelsTrackYouTube) { Text("YouTube Shorts") }

                Stepper(value: $reelsLimit, in: 0...180, step: 5) {
                    HStack {
                        Text("Daily limit")
                        Spacer()
                        Text(reelsLimit == 0 ? "Off (count only)" : "\(reelsLimit) min")
                            .foregroundColor(.secondary)
                    }
                }

                Defaults.Toggle(key: .reelsAutoRedirect) {
                    Text("Redirect the tab once the limit is hit")
                }

                Picker("Show in notch", selection: $reelsNotchMetric) {
                    Text("Reel count").tag("count")
                    Text("Watch time").tag("time")
                    Text("Count + time").tag("both")
                }

                HStack {
                    statTile(title: "Reels today",
                             value: "\(reels.todayCount)",
                             sub: reels.isOnReels ? "watching now" : "scrolled")
                    Divider().frame(height: 32)
                    statTile(title: "Time today",
                             value: focusTimeString(reels.todaySeconds),
                             sub: "\(reels.todayOpens) opens")
                    Divider().frame(height: 32)
                    statTile(title: "This week",
                             value: "\(reels.weekCount())",
                             sub: focusTimeString(reels.weekSeconds()))
                }
                Button(role: .destructive) { reels.resetStats() } label: {
                    Text("Reset reels stats")
                }
            }
        } header: {
            Text("Distraction Blocker")
        } footer: {
            Text("Counts time on Instagram Reels / YouTube Shorts in Chrome, Safari and Atlas, nudges you while scrolling, and redirects the tab once you pass the daily limit. Browser-only; macOS will ask for Automation permission the first time.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func chooseCustomChime() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff, .mpeg4Audio]
        panel.message = "Choose an audio file to use as your chime / ringtone"
        if panel.runModal() == .OK, let url = panel.url {
            customChimePath = url.path
            chimeSound = "Custom"
        }
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
