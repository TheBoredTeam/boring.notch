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
    
    // State management
    var isEnabled: () -> Bool
    var setEnabled: (Bool) -> Void
    
    // Configuration view
    var settingsView: () -> AnyView
    
    // Computed property for easy binding
    var binding: Binding<Bool> {
        Binding(
            get: { isEnabled() },
            set: { setEnabled($0) }
        )
    }
}
