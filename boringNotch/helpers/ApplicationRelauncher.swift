//
//  ApplicationRelauncher.swift
//  boringNotch
//
//  Created by Corentin132 on 03/10/2025.
//

import AppKit

enum ApplicationRelauncher {
    static func restart() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let workspace = NSWorkspace.shared

        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        workspace.openApplication(at: appURL, configuration: configuration, completionHandler: nil)

        NSApplication.shared.terminate(nil)
    }
}
