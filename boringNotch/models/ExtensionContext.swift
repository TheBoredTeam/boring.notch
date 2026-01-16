//
//  ExtensionContext.swift
//  boringNotch
//
//  Created on 2026-01-16.
//  Context object that provides dependencies to extension content providers
//

import SwiftUI

/// Context passed to extension content providers containing all dependencies
/// Extensions use this to access view models, managers, and namespaces
@MainActor
struct ExtensionContext {
    let vm: BoringViewModel
    let albumArtNamespace: Namespace.ID?
    let webcamManager: WebcamManager
    let batteryModel: BatteryStatusViewModel
    
    init(
        vm: BoringViewModel,
        albumArtNamespace: Namespace.ID? = nil,
        webcamManager: WebcamManager = .shared,
        batteryModel: BatteryStatusViewModel = .shared
    ) {
        self.vm = vm
        self.albumArtNamespace = albumArtNamespace
        self.webcamManager = webcamManager
        self.batteryModel = batteryModel
    }
}
