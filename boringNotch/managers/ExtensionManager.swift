//
//  ExtensionManager.swift
//  boringNotch
//
//  Created by sleepy on 2026. 01. 14..
//

import SwiftUI
import Combine
import Defaults

@MainActor
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
        fetchMarketplaceExtensions()
        
        // Observe changes to installed/downloaded lists
        Defaults.publisher(.installedExtensions)
            .sink { [weak self] _ in self?.refreshExtensions() }
            .store(in: &cancellables)
            
        Defaults.publisher(.downloadedExtensions)
            .sink { [weak self] _ in self?.refreshExtensions() }
            .store(in: &cancellables)
            
        // Observe enabled states to trigger UI updates if needed
        // For simple built-ins, re-rendering the list is enough usually.
    }
    
    private func performMigration() {
        var initialInstalled: [String] = []
        for ext in registry.builtInExtensions {
            // Check if feature is currently enabled
            if ext.isEnabled?() ?? false {
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
        let downloadedIDs = Set(Defaults[.downloadedExtensions])
        let enabledIDs = Set(Defaults[.enabledExtensions])
        
        var installed: [ExtensionDescriptor] = []
        
        // 1. Built-ins are always "Installed"
        installed.append(contentsOf: registry.builtInExtensions)
        
        // 2. Downloaded Marketplace items are "Installed"
        // We use the cached marketplace definitions for now. In real app, we'd load metadata from disk/bundle.
        let downloadedItems = marketplaceExtensions.filter { downloadedIDs.contains($0.id) }
        
        // Map downloaded items to have the correct Enabled/Disabled logic using Defaults[.enabledExtensions]
        let configuredDownloadedItems = downloadedItems.map { desc -> ExtensionDescriptor in
            let id = desc.id
            var newDesc = desc
            
            newDesc.isEnabled = {
                Defaults[.enabledExtensions].contains(id)
            }
            
            newDesc.setEnabled = { enabled in
                var current = Defaults[.enabledExtensions]
                if enabled {
                    if !current.contains(id) { current.append(id) }
                } else {
                    current.removeAll { $0 == id }
                }
                Defaults[.enabledExtensions] = current
                // Trigger refresh to update UI state if needed, though binding usually handles it
                self.objectWillChange.send()
            }
            
            return newDesc
        }
        
        installed.append(contentsOf: configuredDownloadedItems)
        
        installedExtensions = installed
        
        // "Available" is now deprecated/empty as per new design
        availableExtensions = []
    }
    
    // Mock Marketplace Data
    @Published var marketplaceExtensions: [ExtensionDescriptor] = []
    
    func fetchMarketplaceExtensions() {
        // Simulating network request delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let mockData = [
                ExtensionDescriptor(
                    id: "com.boring.spotify-mini",
                    name: "[DEMO] Spotify Mini",
                    description: "Demo extension - non-functional placeholder for marketplace preview.",
                    icon: "play.circle.fill",
                    developer: "Demo Developer",
                    version: "1.0.0"
                ),
                ExtensionDescriptor(
                    id: "com.boring.focus-timer",
                    name: "[DEMO] Focus Timer",
                    description: "Demo extension - non-functional placeholder for marketplace preview.",
                    icon: "timer",
                    developer: "Demo Developer",
                    version: "0.5.0"
                )
            ]
            
            self.marketplaceExtensions = mockData
            self.refreshExtensions()
        }
    }
    
    // Actions
    
    func download(extensionID: String) {
        var downloaded = Defaults[.downloadedExtensions]
        if !downloaded.contains(extensionID) {
            downloaded.append(extensionID)
            Defaults[.downloadedExtensions] = downloaded
            
            // Auto-enable upon download?
            var enabled = Defaults[.enabledExtensions]
            if !enabled.contains(extensionID) {
                enabled.append(extensionID)
                Defaults[.enabledExtensions] = enabled
            }
            
            refreshExtensions()
        }
    }
    
    // "Install" is now synonymous with "Download" in the new flow, or enabling.
    // We keep this named 'download' for clarity of action from Marketplace.
    
    func uninstall(extensionID: String) {
        // Remove from downloaded list
        var downloaded = Defaults[.downloadedExtensions]
        downloaded.removeAll { $0 == extensionID }
        Defaults[.downloadedExtensions] = downloaded
        
        // Remove from enabled list
        var enabled = Defaults[.enabledExtensions]
        enabled.removeAll { $0 == extensionID }
        Defaults[.enabledExtensions] = enabled
        
        // If built-in, we just disable it
        if let ext = registry.builtInExtensions.first(where: { $0.id == extensionID }) {
            ext.setEnabled?(false)
        }
        
        refreshExtensions()
    }
    
    // MARK: - Extension Point Methods
    
    /// Get all enabled extensions that support a given extension point
    func extensions(for point: ExtensionPoint) -> [ExtensionDescriptor] {
        installedExtensions
            .filter { $0.isEnabled?() ?? false }
            .filter { $0.supportedPoints.contains(point) }
            .sorted { ($0.contentProvider?().priority ?? 50) > ($1.contentProvider?().priority ?? 50) }
    }
    
    /// Get all enabled extensions that have navigation tabs
    func tabExtensions() -> [ExtensionDescriptor] {
        extensions(for: .navigationTab)
    }
    
    /// Get the highest priority extension for exclusive extension points
    func primaryExtension(for point: ExtensionPoint) -> ExtensionDescriptor? {
        extensions(for: point).first
    }
    
    /// Render all views for a given extension point
    func renderViews(for point: ExtensionPoint) -> [AnyView] {
        extensions(for: point).compactMap { ext in
            ext.contentProvider?().view(for: point)
        }
    }
    
    /// Get settings view for a specific extension (by ID)
    func settingsView(for extensionID: String) -> AnyView? {
        // First check if extension has a contentProvider with settings
        if let ext = installedExtensions.first(where: { $0.id == extensionID }) {
            if let provider = ext.contentProvider?(), provider.hasSettings {
                return provider.settingsView()
            }
            // Fallback to legacy settingsView property
            return ext.settingsView?()
        }
        return nil
    }
    
    /// Check if an extension has settings available
    func hasSettings(for extensionID: String) -> Bool {
        if let ext = installedExtensions.first(where: { $0.id == extensionID }) {
            if let provider = ext.contentProvider?() {
                return provider.hasSettings
            }
            return ext.settingsView != nil
        }
        return false
    }
}

