//
//  LiveActivitySettingsView.swift
//  boringNotch
//
//  Controls for the ambient activities that appear in the closed notch.
//

import Defaults
import EventKit
import SwiftUI

struct LiveActivitySettingsView: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.meetingLiveActivity) private var meetingEnabled
    @Default(.meetingLeadTimeMinutes) private var leadTime
    @Default(.meetingLingerMinutes) private var linger

    private let leadTimeOptions = [1, 2, 5, 10, 15]

    private var hasCalendarAccess: Bool {
        calendarManager.calendarAuthorizationStatus == .fullAccess
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .meetingLiveActivity) {
                    Text("Show meetings in the notch")
                }
                .disabled(!hasCalendarAccess)
            } header: {
                Text("Meetings")
            } footer: {
                if hasCalendarAccess {
                    Text("A meeting appears in the closed notch shortly before it starts. Open the notch to join it in one click.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Calendar access is required. Grant it in the Calendar settings tab.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Picker("Show it", selection: $leadTime) {
                    ForEach(leadTimeOptions, id: \.self) { minutes in
                        Text(beforeLabel(minutes)).tag(minutes)
                    }
                }

                Picker("Keep showing for", selection: $linger) {
                    ForEach([0, 2, 5, 10], id: \.self) { minutes in
                        Text(afterLabel(minutes)).tag(minutes)
                    }
                }

                Defaults.Toggle(key: .meetingRequiresJoinLink) {
                    Text("Only meetings with a video link")
                }
            } footer: {
                Text("Events that were declined, all-day events, birthdays and reminders never appear. Dismissing a meeting hides it until the app restarts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!meetingEnabled || !hasCalendarAccess)

            Section {
                Defaults.Toggle(key: .microphoneLiveActivity) {
                    Text("Show when the microphone is in use")
                }
            } header: {
                Text("Microphone")
            } footer: {
                Text(
                    """
                    Mirrors the orange dot in the menu bar: it appears whenever any app has the \
                    microphone open, including macOS dictation. Boring Notch only reads whether \
                    the input device is running — it never records audio and needs no microphone \
                    permission of its own.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(
                        """
                        Screen recording by other apps is not shown. macOS provides no public way \
                        for an app to learn that another app is capturing the screen, and guessing \
                        from a list of known recorder apps would be wrong as often as it was right.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Live Activities")
    }

    private func beforeLabel(_ minutes: Int) -> String {
        String(
            format: NSLocalizedString("meeting_lead_before", comment: "Lead time option, e.g. '2 minutes before'"),
            minutes
        )
    }

    private func afterLabel(_ minutes: Int) -> String {
        guard minutes > 0 else {
            return NSLocalizedString("meeting_linger_none", comment: "Option: stop showing once the meeting starts")
        }
        return String(
            format: NSLocalizedString("meeting_linger_after", comment: "Linger option, e.g. '5 minutes after it starts'"),
            minutes
        )
    }
}
