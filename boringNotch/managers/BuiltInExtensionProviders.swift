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
        MusicManager.shared.isPlaying ? 100 : 30
    }
    
    var displayOrder: Int { 10 }  // Leftmost position
    
    var hasSettings: Bool { true }
    
    func view(for point: ExtensionPoint, context: ExtensionContext) -> AnyView? {
        switch point {
        case .notchContent:
            guard let namespace = context.albumArtNamespace else { return nil }
            return AnyView(
                MusicPlayerView(albumArtNamespace: namespace)
                    .environmentObject(context.vm)
            )
        case .backgroundAmbient:
            // Music visualizer - could be added here
            return nil
        default:
            return nil
        }
    }
    
    func settingsView() -> AnyView? {
        AnyView(Media())
    }
}

// MARK: - Calendar Extension Provider

@MainActor
class CalendarContentProvider: ExtensionContentProvider {
    var extensionID: String { "calendar" }
    
    var supportedPoints: Set<ExtensionPoint> {
        [.notchContent, .statusIndicators, .settings]
    }
    
    var priority: Int { 80 }
    
    var displayOrder: Int { 20 }  // Middle position
    
    var hasSettings: Bool { true }
    
    func view(for point: ExtensionPoint, context: ExtensionContext) -> AnyView? {
        switch point {
        case .notchContent:
            let shouldShowCamera = Defaults[.showMirror] && 
                context.webcamManager.cameraAvailable && 
                context.vm.isCameraExpanded
            return AnyView(
                CalendarView()
                    .frame(width: shouldShowCamera ? 170 : 215)
                    .onHover { isHovering in
                        context.vm.isHoveringCalendar = isHovering
                    }
                    .environmentObject(context.vm)
                    .transition(.opacity)
            )
        case .statusIndicators:
            // Calendar icon indicator could go here
            return nil
        default:
            return nil
        }
    }
    
    func settingsView() -> AnyView? {
        AnyView(CalendarSettings())
    }
}

// MARK: - Battery Extension Provider

@MainActor
class BatteryContentProvider: ExtensionContentProvider {
    var extensionID: String { "battery" }
    
    var supportedPoints: Set<ExtensionPoint> {
        [.statusIndicators, .settings]
    }
    
    var priority: Int { 50 }
    
    var hasSettings: Bool { true }
    
    func view(for point: ExtensionPoint, context: ExtensionContext) -> AnyView? {
        switch point {
        case .statusIndicators:
            // Battery indicator view - use batteryModel from context
            return AnyView(
                BoringBatteryView(
                    batteryWidth: 26,
                    isCharging: context.batteryModel.isCharging,
                    isInLowPowerMode: context.batteryModel.isInLowPowerMode,
                    isPluggedIn: context.batteryModel.isPluggedIn,
                    levelBattery: context.batteryModel.levelBattery,
                    maxCapacity: context.batteryModel.maxCapacity,
                    timeToFullCharge: context.batteryModel.timeToFullCharge
                )
                .environmentObject(context.vm)
            )
        default:
            return nil
        }
    }
    
    func settingsView() -> AnyView? {
        AnyView(Charge())
    }
}

// MARK: - HUD Extension Provider

@MainActor
class HUDContentProvider: ExtensionContentProvider {
    var extensionID: String { "hud" }
    
    var supportedPoints: Set<ExtensionPoint> {
        [.hudOverlay, .settings]
    }
    
    var priority: Int { 100 }  // HUD is always high priority when triggered
    
    var hasSettings: Bool { true }
    
    func view(for point: ExtensionPoint, context: ExtensionContext) -> AnyView? {
        switch point {
        case .hudOverlay:
            // HUD overlay is handled separately by the HUD system
            // This would return the HUD view when we integrate it
            return nil
        default:
            return nil
        }
    }
    
    func settingsView() -> AnyView? {
        AnyView(HUD())
    }
}

// MARK: - Shelf Extension Provider

@MainActor
class ShelfContentProvider: ExtensionContentProvider {
    var extensionID: String { "shelf" }
    
    var supportedPoints: Set<ExtensionPoint> {
        [.navigationTab, .settings]
    }
    
    var priority: Int { 60 }
    
    var tabIcon: String? { "books.vertical" }
    var tabTitle: String? { "Shelf" }
    
    var hasSettings: Bool { true }
    
    func view(for point: ExtensionPoint, context: ExtensionContext) -> AnyView? {
        switch point {
        case .navigationTab:
            // Shelf view for the navigation tab
            return AnyView(
                ShelfView()
                    .environmentObject(context.vm)
            )
        default:
            return nil
        }
    }
    
    func settingsView() -> AnyView? {
        AnyView(Shelf())
    }
}

// MARK: - Camera Mirror Extension Provider

@MainActor
class CameraContentProvider: ExtensionContentProvider {
    var extensionID: String { "camera" }
    
    var supportedPoints: Set<ExtensionPoint> {
        [.notchContent, .settings]
    }
    
    var priority: Int { 40 }  // Low priority, shows when nothing else is active
    
    var displayOrder: Int { 30 }  // Rightmost position
    
    var hasSettings: Bool { true }
    
    func view(for point: ExtensionPoint, context: ExtensionContext) -> AnyView? {
        switch point {
        case .notchContent:
            // Only show camera when it's actually expanded and available
            guard context.webcamManager.cameraAvailable && context.vm.isCameraExpanded else {
                return nil
            }
            
            let isVisible = context.vm.notchState != .closed
            return AnyView(
                CameraPreviewView(webcamManager: context.webcamManager)
                    .scaledToFit()
                    .opacity(isVisible ? 1 : 0)
                    .blur(radius: isVisible ? 0 : 20)
                    .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0), value: isVisible)
            )
        default:
            return nil
        }
    }
    
    func settingsView() -> AnyView? {
        AnyView(MirrorSettings())
    }
}
