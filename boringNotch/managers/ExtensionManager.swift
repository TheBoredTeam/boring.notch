//
//  ExtensionManager.swift
//  boringNotch
//
//  Created by sleepy on 2026. 01. 14..
//

import SwiftUI
import Combine
import Defaults

class ExtensionManager: ObservableObject {
    static let shared = ExtensionManager()
    
    @Published var installedExtensions: [ExtensionDescriptor] = []
    @Published var availableExtensions: [ExtensionDescriptor] = []
    
    private var registry = ExtensionRegistry.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Migration: If first run with extensions, populate installed based on enabled state
        if !UserDefaults.standard.bool(forKey: "hasMigratedToExtensions") {
            performMigration()
        }
        
        // Initial Load
        refreshExtensions()
        
        // Observe changes to installedExtensions list
        Defaults.publisher(.installedExtensions)
            .sink { [weak self] _ in
                self?.refreshExtensions()
            }
            .store(in: &cancellables)
            
        // Observe enabled states to trigger UI updates if needed
        // For simple built-ins, re-rendering the list is enough usually.
    }
    
    private func performMigration() {
        var initialInstalled: [String] = []
        for ext in registry.builtInExtensions {
            // Check if feature is currently enabled
            if ext.isEnabled() {
                initialInstalled.append(ext.id)
            }
            // Optional: Force install specific core extensions if desired
            // if ext.id == "media" ...
        }
        
        // If NO extensions are enabled, we might want to default to installing all
        // to avoid an empty "Installed" list for a new user (who has defaults=false? No, defaults usually true).
        // Defaults in Constants.swift are mostly true (e.g. boringShelf=true, battery=true).
        // So checking isEnabled() is safe.
        
        Defaults[.installedExtensions] = initialInstalled
        UserDefaults.standard.set(true, forKey: "hasMigratedToExtensions")
    }
    
    func refreshExtensions() {
        let installedIDs = Set(Defaults[.installedExtensions])
        
        installedExtensions = registry.builtInExtensions.filter { installedIDs.contains($0.id) }
        availableExtensions = registry.builtInExtensions.filter { !installedIDs.contains($0.id) }
    }
    
    // Actions
    func install(extensionID: String) {
        var current = Defaults[.installedExtensions]
        if !current.contains(extensionID) {
            current.append(extensionID)
            Defaults[.installedExtensions] = current
            
            // Auto-enable upon install?
            if let ext = registry.builtInExtensions.first(where: { $0.id == extensionID }) {
                ext.setEnabled(true)
            }
        }
    }
    
    func uninstall(extensionID: String) {
        var current = Defaults[.installedExtensions]
        if let index = current.firstIndex(of: extensionID) {
            current.remove(at: index)
            Defaults[.installedExtensions] = current
            
            // Auto-disable upon uninstall?
            if let ext = registry.builtInExtensions.first(where: { $0.id == extensionID }) {
                ext.setEnabled(false)
            }
        }
    }
}
