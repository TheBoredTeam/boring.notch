//
//  BoringExtensionManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 07/09/24.
//

import Foundation
import SwiftUI

var clipboardExtension: String = "theboringteam.TheBoringClipboard"
var hudExtension: String = "theboringteam.TheBoringHUDs"
var downloadManagerExtension: String = "theboringteam.TheBoringDownloadManager"

struct Extension: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var bundleIdentifier: String
    var status: StatusModel = .enabled
}

enum StatusModel {
    case disabled
    case enabled
}

class BoringExtensionManager: ObservableObject {
    
    @Published var installedExtensions: [Extension] = [] {
        didSet {
            print("Extensions installed: \(installedExtensions)")
        }
    }
    
    var extensions = [
        clipboardExtension,
        hudExtension
    ]

    init() {
        checkIfExtensionsAreInstalled()

        DistributedNotificationCenter.default().addObserver(self, selector: #selector(checkIfExtensionsAreInstalled), name: NSNotification.Name("NSWorkspaceDidLaunchApplicationNotification"), object: nil)
    }

    @objc func checkIfExtensionsAreInstalled() {
        installedExtensions = []
        for extensionName in extensions {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: extensionName) != nil {
                let ext = Extension(name: extensionName.components(separatedBy: ".").last ?? extensionName, bundleIdentifier: extensionName)
                installedExtensions.append(ext)
            }
        }
    }
}
