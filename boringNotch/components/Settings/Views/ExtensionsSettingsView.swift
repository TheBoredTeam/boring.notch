//
//  ExtensionsSettingsView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct ExtensionsSettingsView: View {
    @ObservedObject private var extensions = ExtensionManager.shared

    private var checkoutURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "BNLockScreenLyricsCheckoutURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 28)).foregroundStyle(Color.effectiveAccent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Lock Screen Lyrics").font(.headline)
                        Text("Your music, on the big screen.").foregroundStyle(.secondary)
                        Text("Animated lyrics and album artwork for your lock screen. Requires Boring Notch and the separately installed extension.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                HStack {
                    Text("$1 · Permanent unlock").font(.callout.weight(.medium))
                    Spacer()
                    if let checkoutURL { Link("Buy Me a Coffee", destination: checkoutURL).buttonStyle(.borderedProminent) }
                    else { Text("Coming soon").foregroundStyle(.secondary) }
                }
                Button("Install extension…", action: extensions.choosePackage)
                Text("After purchase, download the .bnplugin file and install it here.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Verify your email before checkout. After your $1 purchase, your permanent key appears on the license page and is also sent by email.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(extensions.installed, id: \.id) { manifest in
                Section {
                    ExtensionLicenseSettings(productID: manifest.id)
                    if let controller = extensions.settingsControllers[manifest.id] {
                        ExtensionSettingsController(controller: controller).frame(minHeight: 380)
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

private struct ExtensionLicenseSettings: View {
    let productID: String
    @ObservedObject private var licenses = ExtensionLicenseStore.shared
    @State private var code = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if licenses.licensedProducts.contains(productID) {
                Label("Permanently unlocked", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                HStack {
                    SecureField("14-character license code", text: $code)
                    Button(licenses.activatingProduct == productID ? "Activating…" : "Activate") {
                        licenses.activate(code: code, productID: productID)
                        code = ""
                    }.disabled(!licenses.isConfigured || licenses.activatingProduct != nil || code.isEmpty)
                }
                if !licenses.isConfigured {
                    Text("Activation will be available when this extension launches.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let message = licenses.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct ExtensionSettingsController: NSViewControllerRepresentable {
    let controller: NSViewController
    func makeNSViewController(context: Context) -> NSViewController { controller }
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
