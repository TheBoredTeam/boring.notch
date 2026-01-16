//
//  BuiltInExtensionProviders.swift
//  boringNotch
//
//  Created on 2026-01-16.
//  Content providers for all built-in extensions
//

import SwiftUI
import Defaults

// MARK: - Media Extension Provider

@MainActor
class MediaContentProvider: ExtensionContentProvider {
    var extensionID: String { "media" }
    
    var supportedPoints: Set<ExtensionPoint> {
        [.notchContent, .backgroundAmbient, .settings]
    }
    
    var priority: Int {
        // High priority when music is playing
        BoringViewCoordinator.shared.musicLiveActivityEnabled ? 100 : 30
    }
    
    var hasSettings: Bool { true }
    
    func view(for point: ExtensionPoint) -> AnyView? {
        switch point {
        case .notchContent:
            // Music player view will be rendered here
            return nil  // TODO: Return actual music player view
        case .backgroundAmbient:
            // Music visualizer
            return nil  // TODO: Return visualizer if enabled
        default:
            return nil
        }
    }
    
    func settingsView() -> AnyView? {
        AnyView(Media())
    }
}

// MARK: - Calendar Extension Provider

class CalendarContentProvider: ExtensionContentProvider {
    var extensionID: String { "calendar" }
    
    var supportedPoints: Set<ExtensionPoint> {
        [.notchContent, .statusIndicators, .settings]
    }
    
    var priority: Int {
        // Higher priority if there's an upcoming event
        80
    }
    
    var hasSettings: Bool { true }
    
    func view(for point: ExtensionPoint) -> AnyView? {
        switch point {
        case .notchContent:
            return nil  // TODO: Return calendar widget view
        case .statusIndicators:
            return nil  // TODO: Return calendar icon indicator
        default:
            return nil
        }
    }
    
    func settingsView() -> AnyView? {
        AnyView(CalendarSettings())
    }
}

// MARK: - Battery Extension Provider

class BatteryContentProvider: ExtensionContentProvider {
    var extensionID: String { "battery" }
    
    var supportedPoints: Set<ExtensionPoint> {
        [.statusIndicators, .settings]
    }
    
    var priority: Int { 50 }
    
    var hasSettings: Bool { true }
    
    func view(for point: ExtensionPoint) -> AnyView? {
        switch point {
        case .statusIndicators:
            return nil  // TODO: Return battery indicator view
        default:
            return nil
        }
    }
    
    func settingsView() -> AnyView? {
        AnyView(Charge())
    }
}

// MARK: - HUD Extension Provider

class HUDContentProvider: ExtensionContentProvider {
    var extensionID: String { "hud" }
    
    var supportedPoints: Set<ExtensionPoint> {
        [.hudOverlay, .settings]
    }
    
    var priority: Int { 100 }  // HUD is always high priority when triggered
    
    var hasSettings: Bool { true }
    
    func view(for point: ExtensionPoint) -> AnyView? {
        switch point {
        case .hudOverlay:
            return nil  // TODO: Return HUD overlay view
        default:
            return nil
        }
    }
    
    func settingsView() -> AnyView? {
        AnyView(HUD())
    }
}

// MARK: - Shelf Extension Provider

class ShelfContentProvider: ExtensionContentProvider {
    var extensionID: String { "shelf" }
    
    var supportedPoints: Set<ExtensionPoint> {
        [.navigationTab, .settings]
    }
    
    var priority: Int { 60 }
    
    var tabIcon: String? { "books.vertical" }
    var tabTitle: String? { "Shelf" }
    
    var hasSettings: Bool { true }
    
    func view(for point: ExtensionPoint) -> AnyView? {
        switch point {
        case .navigationTab:
            return nil  // TODO: Return full shelf view
        default:
            return nil
        }
    }
    
    func settingsView() -> AnyView? {
        AnyView(Shelf())
    }
}

// MARK: - Camera Mirror Extension Provider

class CameraContentProvider: ExtensionContentProvider {
    var extensionID: String { "camera" }
    
    var supportedPoints: Set<ExtensionPoint> {
        [.notchContent, .settings]
    }
    
    var priority: Int { 40 }  // Low priority, shows when nothing else is active
    
    var hasSettings: Bool { true }
    
    func view(for point: ExtensionPoint) -> AnyView? {
        switch point {
        case .notchContent:
            return nil  // TODO: Return camera mirror view
        default:
            return nil
        }
    }
    
    func settingsView() -> AnyView? {
        AnyView(MirrorSettings())
    }
}
