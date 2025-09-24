import SwiftUI
import Defaults
import AppKit
import UniformTypeIdentifiers

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

                Slider(value: maxItemsBinding, in: 25...100, step: 5) {
                    Text("Maximum items")
                }
                Text("\(maxItems) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Clipboard History")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Clipboard events from these apps are ignored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if excludedApps.isEmpty {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                            .overlay(
                                VStack(spacing: 6) {
                                    Image(systemName: "app.dashed")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                    Text("No apps excluded")
                                        .font(.headline)
                                    Text("Click Add to pick an application.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(16)
                            )
                            .frame(height: 110)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(excludedApps, id: \.self) { bundleID in
                                ExcludedAppRow(bundleIdentifier: bundleID) {
                                    removeBundleID(bundleID)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.secondary.opacity(0.15))
                        )
                    }

                    HStack {
                        Button {
                            presentApplicationPicker()
                        } label: {
                            Label("Add Application", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)

                        if !excludedApps.isEmpty {
                            Button("Clear All", role: .destructive) {
                                excludedApps.removeAll()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } header: {
                Text("Privacy")
            }
        }
        .navigationTitle("Clipboard")
    }

    private func presentApplicationPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Application"
        panel.message = "Pick an application whose clipboard activity should be ignored."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return }
            if excludedApps.contains(identifier) { return }
            DispatchQueue.main.async {
                withAnimation {
                    excludedApps.append(identifier)
                }
            }
        }
    }

    private func removeBundleID(_ bundleID: String) {
        guard let index = excludedApps.firstIndex(of: bundleID) else { return }
        withAnimation {
            excludedApps.remove(at: index)
        }
    }
}

private struct ExcludedAppRow: View {
    let bundleIdentifier: String
    let onRemove: () -> Void

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    private var displayName: String {
        if let url = appURL,
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        {
            return name
        }
        return bundleIdentifier
    }

    private var icon: NSImage? {
        if let url = appURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon)))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                Text(bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}
