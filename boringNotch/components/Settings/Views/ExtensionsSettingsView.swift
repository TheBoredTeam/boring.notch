// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ExtensionsSettingsView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case store
        case installed

        var id: Self { self }
        var title: LocalizedStringKey { self == .store ? "Store" : "Installed" }
    }

    @ObservedObject private var extensions = ExtensionManager.shared
    @ObservedObject private var store = ExtensionStore.shared
    @State private var selectedTab: Tab = .store
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Extensions", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            switch selectedTab {
            case .store:
                ExtensionStoreView(onManageInstalled: { selectedTab = .installed })
            case .installed:
                installedExtensions
            }
        }
        .navigationTitle("Extensions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Install from file…", systemImage: "plus", action: extensions.choosePackage)
                    .disabled(extensions.isInstalling || store.activeDownloadID != nil)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: installDrop)
    }

    private var installedExtensions: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Add an extension", systemImage: "puzzlepiece.extension")
                        .font(.headline)
                    Text("Drop a ZIP or .bnplugin bundle here, or choose a file.")
                        .foregroundStyle(.secondary)
                    Button("Install extension…", action: extensions.choosePackage)
                        .disabled(extensions.isInstalling || store.activeDownloadID != nil)
                    if extensions.isInstalling {
                        ProgressView("Checking extension…")
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Install an extension from a ZIP or bundle")

                if let documentation = URL(string: "https://github.com/TheBoredTeam/boring.notch/blob/dev/docs/extensions.md") {
                    Link("Build an extension", destination: documentation)
                }
            } footer: {
                Text("Extensions come from independent developers. Each developer manages their own purchase and access settings. You'll review the publisher before installation.")
            }

            if extensions.installed.isEmpty {
                Section {
                    Text("No extensions installed")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(extensions.installed, id: \.id) { manifest in
                Section {
                    LabeledContent("Version", value: manifest.version)
                    if extensions.enabledIDs.contains(manifest.id) {
                        if let controller = extensions.settingsControllers[manifest.id] {
                            ExtensionSettingsController(controller: controller)
                                .frame(minHeight: settingsHeight(controller))
                        }
                        Button("Disable extension") { extensions.disable(manifest) }
                            .disabled(extensions.isInstalling)
                    } else {
                        Button("Review and enable…") { extensions.enable(manifest) }
                            .disabled(extensions.isInstalling)
                    }
                    Button("Uninstall extension", role: .destructive) { extensions.remove(manifest) }
                        .disabled(extensions.isInstalling)
                } header: { Text(manifest.name) }
            }

            if let message = extensions.message {
                Section {
                    Text(message).font(.callout)
                    if extensions.needsRestart {
                        Button("Restart Boring Notch") { ApplicationRelauncher.restart() }
                    }
                }
            }
        }
    }

    private func installDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !extensions.isInstalling, store.activeDownloadID == nil else { return false }
        guard providers.count == 1, let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            extensions.message = "Drop one extension ZIP or bundle at a time."
            return false
        }
        selectedTab = .installed
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            Task { @MainActor in
                guard let url, url.isFileURL else {
                    extensions.message = "The dropped file could not be opened."
                    return
                }
                extensions.install(from: url)
            }
        }
        return true
    }

    private func settingsHeight(_ controller: NSViewController) -> CGFloat {
        let requested = controller.preferredContentSize.height
        return requested.isFinite && requested > 0 ? min(1_400, max(200, requested)) : 380
    }
}

@MainActor
private struct ExtensionSettingsController: NSViewControllerRepresentable {
    let controller: NSViewController
    func makeNSViewController(context: Context) -> NSViewController { controller }
    func updateNSViewController(_ controller: NSViewController, context: Context) {}
}
