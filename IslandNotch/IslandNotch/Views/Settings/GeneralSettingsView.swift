//  GeneralSettingsView.swift
//  IslandNotch
//
//  Purpose: Capture-folder location, retention sweep, and which capture sources
//           auto-copy the pasteable payload to the clipboard.
//  Layer: View

import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section("Screenshots folder") {
                Picker("Save to", selection: $preferences.captureLocation) {
                    ForEach(CaptureLocation.allCases) { location in
                        Text(location.displayName).tag(location)
                    }
                }
                Text(preferences.captureLocation.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Housekeeping") {
                Stepper(value: $preferences.retentionDays, in: 0...365) {
                    Text(preferences.retentionDays == 0
                         ? "Keep screenshots forever"
                         : "Delete shots older than \(preferences.retentionDays) day\(preferences.retentionDays == 1 ? "" : "s")")
                }
            }

            Section("Auto-copy to clipboard") {
                Text("Choose which capture methods automatically copy the payload. Others require a left-click on the thumbnail.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(CaptureSource.allCases) { source in
                    Toggle(source.displayName, isOn: autoCopyBinding(for: source))
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Toggle that adds/removes a source from the auto-copy set.
    private func autoCopyBinding(for source: CaptureSource) -> Binding<Bool> {
        Binding(
            get: { preferences.autoCopySources.contains(source) },
            set: { isOn in
                if isOn { preferences.autoCopySources.insert(source) }
                else { preferences.autoCopySources.remove(source) }
            }
        )
    }
}
