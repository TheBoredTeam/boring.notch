//
//  TeleprompterSettingsView.swift
//  boringNotch
//
//  Settings pane for the teleprompter. Script editing happens here (rather than
//  in the notch) because the notch panel can't take keyboard focus.
//

import SwiftUI
import Defaults

extension Notification.Name {
    /// Posted with a tab identifier in `userInfo["tab"]` to deep-link the
    /// Settings window to a specific pane.
    static let openSettingsTab = Notification.Name("openSettingsTab")
}

/// Opens the Settings window on the Teleprompter pane.
enum TeleprompterSettingsRoute {
    static let tabIdentifier = "Teleprompter"

    @MainActor
    static func open() {
        SettingsWindowController.shared.showWindow()
        NotificationCenter.default.post(
            name: .openSettingsTab,
            object: nil,
            userInfo: ["tab": tabIdentifier]
        )
    }
}

struct TeleprompterSettings: View {
    @StateObject private var model = TeleprompterViewModel.shared
    @State private var micAuthorized = SpeechFollower.isAuthorized
    @Default(.notchOpenHeight) var notchHeight
    @Default(.notchOpenWidth) var notchWidth

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableTeleprompter) {
                    Text("Show teleprompter tab")
                }
            } footer: {
                Text("Adds a Teleprompter tab to the open notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $model.scriptText)
                    .font(.body)
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor)))
                HStack {
                    Text("\(model.words.count) words")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { model.scriptText = "" }
                        .disabled(model.scriptText.isEmpty)
                }
                .font(.caption)
            } header: {
                Text("Script")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { model.followVoice },
                    set: { model.setFollowVoice($0) }
                )) {
                    Text("Follow my voice")
                }
                if model.followVoice {
                    HStack {
                        Image(systemName: micAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(micAuthorized ? .green : .orange)
                        Text(micAuthorized
                             ? "Microphone and speech access granted"
                             : "Microphone access is required to follow your voice")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                        if !micAuthorized {
                            Button("Grant Access") {
                                Task {
                                    _ = await SpeechFollower.requestAuthorization()
                                    micAuthorized = SpeechFollower.isAuthorized
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Voice following")
            } footer: {
                Text("As you speak, the spoken words are highlighted and the text scrolls to keep pace. Recognition runs on-device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .teleprompterArrowKeys) {
                    Text("Scroll with arrow keys")
                }
            } header: {
                Text("Manual control")
            } footer: {
                Text("↑ / ↓ move by line, ← / → by word, Space plays or pauses. Works while another app is focused when boring.notch is allowed under Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Text size")
                    Slider(value: $model.fontSize, in: 12...40, step: 1)
                    Text("\(Int(model.fontSize))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
                Toggle(isOn: $model.mirror) {
                    Text("Mirror text (for reflective glass)")
                }
            } header: {
                Text("Appearance")
            }

            Section {
                HStack {
                    Text("Height")
                    Slider(value: $notchHeight, in: 190...380, step: 10)
                    Text("\(Int(notchHeight))")
                        .monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                HStack {
                    Text("Width")
                    Slider(value: $notchWidth, in: 560...820, step: 10)
                    Text("\(Int(notchWidth))")
                        .monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                Button("Reset to default size") {
                    notchHeight = 190
                    notchWidth = 640
                }
                .disabled(notchHeight == 190 && notchWidth == 640)
            } header: {
                Text("Notch size")
            } footer: {
                Text("Resizes the whole open notch. Triple-click the notch to hide it; drag down at the top-center — or use the menu-bar icon, or ⌘⇧I — to bring it back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Teleprompter")
        .onAppear { micAuthorized = SpeechFollower.isAuthorized }
    }
}

#Preview {
    TeleprompterSettings()
        .frame(width: 700, height: 600)
}
