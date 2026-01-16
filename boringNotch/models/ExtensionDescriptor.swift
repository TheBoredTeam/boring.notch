//
//  ExtensionDescriptor.swift
//  boringNotch
//
//  Created by sleepy on 2026. 01. 14..
//

import SwiftUI
import Defaults

struct ExtensionDescriptor: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let developer: String
    let version: String
    let isBuiltIn: Bool
    
    // State management (Optional for remote extensions)
    var isEnabled: (() -> Bool)?
    var setEnabled: ((Bool) -> Void)?
    
    // Configuration view (Optional - legacy, prefer contentProvider)
    var settingsView: (() -> AnyView)?
    
    // MARK: - Extension Point System (NEW)
    
    /// Which extension points this extension supports
    var supportedPoints: Set<ExtensionPoint> = []
    
    /// Content provider for rendering at extension points
    var contentProvider: (() -> AnyExtensionContentProvider)?
    
    /// Whether user can delete this extension (false for built-ins)
    var canDelete: Bool { !isBuiltIn }
    
    /// Tab icon for .navigationTab point
    var tabIcon: String?
    
    /// Tab title for .navigationTab point
    var tabTitle: String?
    
    // Computed property for easy binding
    var binding: Binding<Bool> {
        Binding(
            get: { isEnabled?() ?? false },
            set: { setEnabled?($0) }
        )
    }
    
    // MARK: - Initializers
    
    // Remote Extension Initializer
    init(id: String, name: String, description: String, icon: String, developer: String, version: String) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.developer = developer
        self.version = version
        self.isBuiltIn = false
        self.isEnabled = nil
        self.setEnabled = nil
        self.settingsView = nil
        self.supportedPoints = []
        self.contentProvider = nil
        self.tabIcon = nil
        self.tabTitle = nil
    }
    
    // Built-in/Full Extension Initializer (Legacy - for backward compatibility)
    init(id: String, name: String, description: String, icon: String, developer: String, version: String, isBuiltIn: Bool, isEnabled: @escaping () -> Bool, setEnabled: @escaping (Bool) -> Void, settingsView: @escaping () -> AnyView) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.developer = developer
        self.version = version
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.setEnabled = setEnabled
        self.settingsView = settingsView
        self.supportedPoints = []
        self.contentProvider = nil
        self.tabIcon = nil
        self.tabTitle = nil
    }
    
    // Full Extension Initializer with Extension Points (NEW)
    init(
        id: String,
        name: String,
        description: String,
        icon: String,
        developer: String,
        version: String,
        isBuiltIn: Bool,
        isEnabled: @escaping () -> Bool,
        setEnabled: @escaping (Bool) -> Void,
        supportedPoints: Set<ExtensionPoint>,
        contentProvider: @escaping () -> AnyExtensionContentProvider,
        tabIcon: String? = nil,
        tabTitle: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.developer = developer
        self.version = version
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.setEnabled = setEnabled
        self.settingsView = nil  // Use contentProvider.settingsView() instead
        self.supportedPoints = supportedPoints
        self.contentProvider = contentProvider
        self.tabIcon = tabIcon
        self.tabTitle = tabTitle
    }
}

