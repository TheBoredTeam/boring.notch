//
//  CaptureSettingsView.swift
//  boringNotch
//
//  Capture settings: where screenshots go, what the colour picker copies, and
//  the Screen Recording permission this all depends on.
//

import Defaults
import SwiftUI

struct CaptureSettingsView: View {
    @Default(.captureEnabled) private var enabled
    @Default(.captureDestination) private var destination
    @Default(.captureColorFormat) private var colorFormat

    /// Permission state is read once on appear and re-read when the user comes
    /// back from System Settings — there is no notification for a TCC grant,
    /// and polling for one would be worse than a refresh on focus.
    @State private var hasPermission = ScreenCaptureService.shared.hasPermission

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .captureEnabled) {
                    Text("Show capture tools")
                }
            } footer: {
                Text("Adds a Capture tab with area, window and full-screen screenshots, text recognition, a colour picker and GIF recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            permissionSection

            Section {
                Picker("Save captures to", selection: $destination) {
                    ForEach(CaptureDestination.allCases) { option in
                        Label(option.localizedTitle, systemImage: option.systemImage).tag(option)
                    }
                }

                Defaults.Toggle(key: .capturePlaySound) {
                    Text("Play the camera sound")
                }
            } header: {
                Text("Screenshots")
            } footer: {
                Text(destinationFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            Section {
                Picker("Copy colours as", selection: $colorFormat) {
                    ForEach(ColorFormat.allCases) { format in
                        Text(format.localizedTitle).tag(format)
                    }
                }
            } header: {
                Text("Colour picker")
            } footer: {
                Text(sampleColorFooter)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Text recognition runs on your Mac.")
                            .font(.caption.weight(.semibold))
                        Text(
                            """
                            Captured images are read by Apple's on-device Vision framework. \
                            Nothing is uploaded, and captures are written only to this app's own \
                            folder unless you choose Save to a file.
                            """
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Capture")
        .onAppear { refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermission()
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if enabled && !hasPermission {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen Recording access is required")
                            .font(.headline)
                        Text("Screenshots, text recognition and GIF recording all need it. The colour picker does not.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        ScreenCaptureService.shared.openScreenRecordingSettings()
                    }
                }
            }
        }
    }

    private var destinationFooter: String {
        switch destination {
        case .shelf:
            return NSLocalizedString(
                "capture_footer_shelf",
                comment: "Explains the shelf destination"
            )
        case .clipboard:
            return NSLocalizedString(
                "capture_footer_clipboard",
                comment: "Explains the clipboard destination"
            )
        case .file:
            return NSLocalizedString(
                "capture_footer_file",
                comment: "Explains the save-to-file destination"
            )
        }
    }

    /// A worked example rather than a description — it is shorter and removes
    /// any doubt about exactly what lands on the clipboard.
    private var sampleColorFooter: String {
        SampledColor(red: 0.2, green: 0.55, blue: 0.9, alpha: 1).string(for: colorFormat)
    }

    private func refreshPermission() {
        hasPermission = ScreenCaptureService.shared.hasPermission
    }
}
