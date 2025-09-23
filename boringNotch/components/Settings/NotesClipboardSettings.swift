import SwiftUI
import Defaults

struct NotesSettings: View {
    @Default(.notesAutoSaveInterval) private var autoSaveInterval

    var body: some View {
        Form {
            Section {
                Defaults.Toggle("Enable Notes", key: .enableNotes)
                Defaults.Toggle("Default to monospace font", key: .notesDefaultMonospace)
                Slider(value: $autoSaveInterval, in: 1...10, step: 1) {
                    Text("Auto-save interval")
                }
                Text("\(Int(autoSaveInterval)) seconds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notes")
            }
        }
        .navigationTitle("Notes")
    }
}

struct ClipboardSettings: View {
    @Default(.clipboardRetentionDays) private var retentionDays
    @Default(.clipboardMaxItems) private var maxItems
    @Default(.clipboardExcludedApps) private var excludedApps

    private var retentionBinding: Binding<Double> {
        Binding(
            get: { Double(retentionDays) },
            set: { retentionDays = Int($0.rounded()) }
        )
    }

    private var maxItemsBinding: Binding<Double> {
        Binding(
            get: { Double(maxItems) },
            set: { maxItems = Int($0.rounded()) }
        )
    }

    private var excludedAppsBinding: Binding<String> {
        Binding(
            get: { excludedApps.joined(separator: "\n") },
            set: { newValue in
                let list = newValue
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                excludedApps = list
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle("Enable clipboard history", key: .enableClipboardHistory)
                Defaults.Toggle("Capture images", key: .clipboardCaptureImages)
                Defaults.Toggle("Capture rich text", key: .clipboardCaptureRichText)

                Slider(value: retentionBinding, in: 1...30, step: 1) {
                    Text("Retention period")
                }
                Text("\(retentionDays) day\(retentionDays == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(value: maxItemsBinding, in: 100...2000, step: 50) {
                    Text("Maximum items")
                }
                Text("\(maxItems) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Clipboard History")
            }

            Section {
                Text("Excluded applications")
                    .font(.headline)
                Text("Clipboard events originating from these bundle identifiers are ignored. Enter one bundle ID per line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: excludedAppsBinding)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    )
            } header: {
                Text("Privacy")
            }
        }
        .navigationTitle("Clipboard")
    }
}
