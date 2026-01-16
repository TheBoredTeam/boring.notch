//
//  ExtensionContentProvider.swift
//  boringNotch
//
//  Created on 2026-01-16.
//

import SwiftUI

/// Protocol that all extensions implement to provide content at extension points
protocol ExtensionContentProvider {
    
    // MARK: - Identity
    
    /// Unique identifier for this extension
    var extensionID: String { get }
    
    // MARK: - Extension Points
    
    /// Which extension points this extension provides content for
    var supportedPoints: Set<ExtensionPoint> { get }
    
    /// Priority for exclusive extension points (higher = more important)
    /// Default is 50. Music playing might be 100, idle camera might be 20.
    var priority: Int { get }
    
    // MARK: - Navigation Tab
    
    /// SF Symbol name for tab icon (required if supporting .navigationTab)
    var tabIcon: String? { get }
    
    /// Title shown under tab (optional)
    var tabTitle: String? { get }
    
    // MARK: - Content
    
    /// Provides the view for a given extension point
    /// - Parameter point: The extension point to render for
    /// - Returns: The view to display, or nil if not supported
    func view(for point: ExtensionPoint) -> AnyView?
    
    // MARK: - Settings
    
    /// Whether this extension has a settings view
    var hasSettings: Bool { get }
    
    /// Returns the settings view for this extension
    func settingsView() -> AnyView?
    
    // MARK: - Lifecycle
    
    /// Called when the extension is enabled
    func onEnable()
    
    /// Called when the extension is disabled
    func onDisable()
}

// MARK: - Default Implementations

extension ExtensionContentProvider {
    var priority: Int { 50 }
    var tabIcon: String? { nil }
    var tabTitle: String? { nil }
    var hasSettings: Bool { false }
    
    func settingsView() -> AnyView? { nil }
    func onEnable() {}
    func onDisable() {}
}

// MARK: - Type-Erased Wrapper

/// Type-erased wrapper for ExtensionContentProvider
/// Allows storing different provider types in collections
struct AnyExtensionContentProvider: ExtensionContentProvider {
    private let _extensionID: () -> String
    private let _supportedPoints: () -> Set<ExtensionPoint>
    private let _priority: () -> Int
    private let _tabIcon: () -> String?
    private let _tabTitle: () -> String?
    private let _view: (ExtensionPoint) -> AnyView?
    private let _hasSettings: () -> Bool
    private let _settingsView: () -> AnyView?
    private let _onEnable: () -> Void
    private let _onDisable: () -> Void
    
    init<P: ExtensionContentProvider>(_ provider: P) {
        _extensionID = { provider.extensionID }
        _supportedPoints = { provider.supportedPoints }
        _priority = { provider.priority }
        _tabIcon = { provider.tabIcon }
        _tabTitle = { provider.tabTitle }
        _view = { provider.view(for: $0) }
        _hasSettings = { provider.hasSettings }
        _settingsView = { provider.settingsView() }
        _onEnable = { provider.onEnable() }
        _onDisable = { provider.onDisable() }
    }
    
    var extensionID: String { _extensionID() }
    var supportedPoints: Set<ExtensionPoint> { _supportedPoints() }
    var priority: Int { _priority() }
    var tabIcon: String? { _tabIcon() }
    var tabTitle: String? { _tabTitle() }
    var hasSettings: Bool { _hasSettings() }
    
    func view(for point: ExtensionPoint) -> AnyView? { _view(point) }
    func settingsView() -> AnyView? { _settingsView() }
    func onEnable() { _onEnable() }
    func onDisable() { _onDisable() }
}
