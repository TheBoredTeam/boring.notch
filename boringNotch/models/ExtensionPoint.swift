//
//  ExtensionPoint.swift
//  boringNotch
//
//  Created on 2026-01-16.
//

import SwiftUI

/// Defines the locations where extensions can provide content
enum ExtensionPoint: String, CaseIterable, Hashable {
    /// Own tab in the navigation bar with full view
    /// Used by: Clipboard, Notes, Shelf
    case navigationTab
    
    /// Main content area in the notch (priority-based, exclusive)
    /// Used by: Music player, Calendar widget
    case notchContent
    
    /// Status indicators in the status area (shared)
    /// Used by: Battery, WiFi, Calendar icon
    case statusIndicators
    
    /// Background/ambient effects layer (shared)
    /// Used by: Music visualizer, effects
    case backgroundAmbient
    
    /// System HUD replacement overlay (exclusive)
    /// Used by: Volume, brightness controls
    case hudOverlay
    
    /// Custom settings view for the extension
    /// Used by: All extensions with configuration
    case settings
}

/// Defines whether multiple extensions can render at the same point
extension ExtensionPoint {
    var isExclusive: Bool {
        switch self {
        case .notchContent, .hudOverlay:
            return true  // Only highest priority renders
        case .navigationTab, .statusIndicators, .backgroundAmbient, .settings:
            return false // Multiple can render together
        }
    }
    
    var displayName: String {
        switch self {
        case .navigationTab: return "Navigation Tab"
        case .notchContent: return "Notch Content"
        case .statusIndicators: return "Status Indicators"
        case .backgroundAmbient: return "Background"
        case .hudOverlay: return "HUD Overlay"
        case .settings: return "Settings"
        }
    }
}
