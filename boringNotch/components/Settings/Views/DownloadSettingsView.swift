//
//  DownloadSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct DownloadSettings: View {
    @Default(.enableDownloadListener) var enableDownloadListener

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableDownloadListener) {
                    Text("Show download activities")
                }
                Defaults.Toggle(key: .downloadStickyActivity) {
                    Text("Keep showing while downloading")
                }
                .disabled(!enableDownloadListener)
            } header: {
                Text("Downloads")
            } footer: {
                HelpText("With the second option off, the notch shows a brief activity when a download starts and finishes, and stays quiet in between. Progress is always available by opening the notch.")
            }

            Section {
                HelpText("Downloads are reported by the app doing the downloading, using the same system mechanism that draws progress on the Dock's Downloads stack. Apps that do not report progress this way cannot be shown, and only your Downloads folder is watched.\n\nmacOS does not reveal which app published a download, so activities show the file's icon rather than an app icon. Some browsers only report a temporary filename while a download is running; in that case the notch says \"Downloading\" until the real name is known.")
            } header: {
                Text("About download detection")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Downloads")
    }
}

#Preview {
    DownloadSettings()
        .frame(width: 500, height: 400)
}
