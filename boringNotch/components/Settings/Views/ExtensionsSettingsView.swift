//
//  ExtensionsSettingsView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct ExtensionsSettingsView: View {
    @ObservedObject private var extensions = ExtensionManager.shared
    var body: some View {
        Form {
            Section {
                Text("Make Boring Notch your own.").font(.headline)
                Text("Install extensions from developers you trust. Extensions may be free or paid; each developer manages their own purchase and access settings.")
                    .foregroundStyle(.secondary)
                Button("Install extension…", action: extensions.choosePackage)
                if let url = URL(string: "https://github.com/TheBoredTeam/boring.notch/blob/dev/docs/extensions.md") {
                    Link("Build an extension", destination: url)
                }
            }
            ForEach(extensions.installed, id: \.id) { manifest in
                Section {
                    if let controller = extensions.settingsControllers[manifest.id] {
                        ExtensionSettingsController(controller: controller)
                            .frame(minHeight: controller.preferredContentSize.height > 0 ? min(1400, max(200, controller.preferredContentSize.height)) : 380)
                    } else {
                        Button("Review and enable…") { extensions.enable(manifest) }
                    }
                    LabeledContent("Version", value: manifest.version)
                    Button("Uninstall extension", role: .destructive) { extensions.remove(manifest) }
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
        }.navigationTitle("Extensions")
    }
}

private struct ExtensionSettingsController: NSViewControllerRepresentable {
    let controller: NSViewController
    func makeNSViewController(context: Context) -> NSViewController { controller }
    func updateNSViewController(_ controller: NSViewController, context: Context) {}
}
