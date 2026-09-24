import AppKit
import SwiftUI

struct DailyPlanningSettingsView: View {
    @ObservedObject private var manager = DailyPlanningManager.shared

    var body: some View {
        Form {
            DailyPlanningSettingsSection()
            Section("Daily conclusion") {
                Toggle("Write a diary after evening review", isOn: Binding(
                    get: { manager.conclusionPreferences.isEnabled },
                    set: { manager.setConclusionEnabled($0) }
                ))
                LabeledContent("Diary folder") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(manager.conclusionPreferences.directoryPath.isEmpty
                             ? "No folder selected" : manager.conclusionPreferences.directoryPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                        Button(manager.conclusionPreferences.directoryBookmark == nil ? "Allow Folder Access…" : "Choose Folder…", action: chooseFolder)
                    }
                }
                Text("Write in Markdown. Entries are saved as YYYY-MM-DD.md in your diary folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if manager.conclusionPreferences.isEnabled && manager.conclusionPreferences.directoryBookmark == nil {
                    Label("Allow folder access before saving your first diary entry.", systemImage: "folder.badge.questionmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let error = manager.conclusionSettingsError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Planning & Review")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Diary Folder"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose Documents to create Boring Notch Diary, or select another folder for your entries."
        if !manager.conclusionPreferences.directoryPath.isEmpty {
            let destination = URL(fileURLWithPath: manager.conclusionPreferences.directoryPath)
            panel.directoryURL = FileManager.default.fileExists(atPath: destination.path)
                ? destination : destination.deletingLastPathComponent()
        }
        if panel.runModal() == .OK, let url = panel.url {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let defaultDirectory = DailyConclusionPreferences.defaultDirectory
            if url.standardizedFileURL == defaultDirectory.deletingLastPathComponent().standardizedFileURL {
                do {
                    try FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: false)
                    manager.setConclusionDirectory(defaultDirectory)
                } catch {
                    // An existing directory is also a valid destination.
                    if (try? defaultDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        manager.setConclusionDirectory(defaultDirectory)
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "The diary folder could not be created."
                        alert.informativeText = "Choose another writable folder and try again."
                        alert.runModal()
                    }
                }
            } else {
                manager.setConclusionDirectory(url)
            }
        }
    }
}

struct DailyPlanningSettingsSection: View {
    @ObservedObject private var manager = DailyPlanningManager.shared

    var body: some View {
        Section(header: Text("Daily Planning & Review")) {
            Toggle(
                "Morning planning",
                isOn: enabledBinding(for: .morningPlanning)
            )
            DatePicker(
                "Planning time",
                selection: timeBinding(for: .morningPlanning),
                displayedComponents: .hourAndMinute
            )
            .disabled(!manager.preferences.morningPlanningEnabled)

            Toggle(
                "Evening review",
                isOn: enabledBinding(for: .eveningReview)
            )
            DatePicker(
                "Review time",
                selection: timeBinding(for: .eveningReview),
                displayedComponents: .hourAndMinute
            )
            .disabled(!manager.preferences.eveningReviewEnabled)
        }
    }

    private func enabledBinding(for kind: DailyWorkflowKind) -> Binding<Bool> {
        Binding(
            get: { manager.preferences.isEnabled(kind) },
            set: { manager.setEnabled($0, for: kind) }
        )
    }

    private func timeBinding(for kind: DailyWorkflowKind) -> Binding<Date> {
        Binding(
            get: { manager.configuredTime(for: kind) },
            set: { manager.setTime($0, for: kind) }
        )
    }
}

