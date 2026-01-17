//
//  ExtensionTabView.swift
//  boringNotch
//
//  Created on 2026-01-16.
//  Renders content for extension tabs dynamically
//

import SwiftUI

/// View that renders content for a specific extension tab
struct ExtensionTabView: View {
    let extensionID: String
    let albumArtNamespace: Namespace.ID
    
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var extensionManager = ExtensionManager.shared
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    
    /// Context for extension content providers
    private var extensionContext: ExtensionContext {
        ExtensionContext(
            vm: vm,
            albumArtNamespace: albumArtNamespace,
            webcamManager: webcamManager,
            batteryModel: batteryModel
        )
    }
    
    var body: some View {
        Group {
            if let ext = extensionManager.installedExtensions.first(where: { $0.id == extensionID }),
               let provider = ext.contentProvider?(),
               let view = provider.view(for: .navigationTab, context: extensionContext) {
                view
            } else {
                // Fallback if extension not found
                VStack(spacing: 16) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Extension not available")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
