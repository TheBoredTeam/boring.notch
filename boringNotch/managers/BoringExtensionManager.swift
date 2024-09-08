//
//  BoringExtensionManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 07/09/24.
//

import Foundation

var clipboardExtension: String = "theboringteam.boringClipboard"
var hudExtension: String = "theboringteam.TheBoringHuds"

class BoringExtensionManager: ObservableObject {
    static let shared = BoringExtensionManager()

    var extensions = [
        clipboardExtension,
        hudExtension
    ]

    @Published var installedExtensions: [String] = [] {
        didSet {
            print("Extensions installed: \(installedExtensions)")
        }
    }

    init() {
        checkIfExtensionsAreInstalled()

        DistributedNotificationCenter.default().addObserver(self, selector: #selector(checkIfExtensionsAreInstalled), name: NSNotification.Name("NSWorkspaceDidLaunchApplicationNotification"), object: nil)
    }

    @objc func checkIfExtensionsAreInstalled() {
        for extensionName in extensions {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: extensionName) != nil {
                installedExtensions.append(extensionName)
            }
        }
    }
}
