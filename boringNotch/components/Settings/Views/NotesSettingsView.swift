//
//  NotesSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct NotesSettings: View {
    @Default(.enableNotes) private var enableNotes
    @Default(.showAppleNotesContent) private var showAppleNotesContent
    @ObservedObject private var notesManager = AppleNotesManager.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableNotes) {
                    Text("Enable Notes")
                }

                Defaults.Toggle(key: .showAppleNotesContent) {
                    Text("Show existing Apple Notes")
                }
                .disabled(!enableNotes)

                Text("Notes created here are saved in the Boring Notch folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("When disabled, only notes created by Boring Notch are shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notes")
            }

            Section {
                Button("Refresh") {
                    Task { await notesManager.refresh() }
                }
                .disabled(!enableNotes || notesManager.isSyncing)

                if notesManager.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }

                if let error = notesManager.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Sync with Apple Notes")
            } footer: {
                Text("Existing Apple Notes are read-only here. Open a note in Notes for attachments, checklists, tables, collaboration, and other native features.")
            }
        }
        .navigationTitle("Notes")
        .onChange(of: showAppleNotesContent) { _, _ in
            Task { await notesManager.refresh() }
        }
    }
}
