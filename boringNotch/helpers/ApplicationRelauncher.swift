//
//  ApplicationRelauncher.swift
//  boringNotch
//
//  Created by Corentin132 on 03/10/2025.
//

import AppKit

@MainActor
enum ApplicationRelauncher {
    static func restart(at appURL: URL? = nil) {
        let workspace = NSWorkspace.shared
        let applicationURL: URL

        if let appURL {
            applicationURL = appURL
        } else {
            guard let bundleIdentifier = Bundle.main.bundleIdentifier,
                  let registeredURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
            else { return }
            applicationURL = registeredURL
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        workspace.openApplication(at: applicationURL, configuration: configuration, completionHandler: nil)

        NSApplication.shared.terminate(nil)
    }
}
