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
    
    // Configuration view (Optional)
    var settingsView: (() -> AnyView)?
    
    // Computed property for easy binding
    var binding: Binding<Bool> {
        Binding(
            get: { isEnabled?() ?? false },
            set: { setEnabled?($0) }
        )
    }
    
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
    }
    
    // Built-in/Full Extension Initializer
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
    }
}
