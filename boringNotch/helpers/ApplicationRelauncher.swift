//
//  ApplicationRelauncher.swift
//  boringNotch
//
//  Created by Corentin132 on 03/10/2025.
//

import AppKit

enum ApplicationRelauncher {
    static func restart() {
        let workspace = NSWorkspace.shared

        // Relaunch the exact copy that is running. Looking the app up by bundle
        // identifier can resolve to another copy (for example an older build in
        // /Applications) and silently restart the wrong binary.
        var appURL = Bundle.main.bundleURL
        if appURL.pathExtension != "app" {
            guard let bundleIdentifier = Bundle.main.bundleIdentifier,
                let installed = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
            else { return }
            appURL = installed
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        workspace.openApplication(at: appURL, configuration: configuration, completionHandler: nil)

        NSApplication.shared.terminate(nil)
    }
}
