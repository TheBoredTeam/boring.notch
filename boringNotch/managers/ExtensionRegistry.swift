//
//  ExtensionRegistry.swift
//  boringNotch
//
//  Created by sleepy on 2026. 01. 14..
//

import SwiftUI
import Defaults

@MainActor
class ExtensionRegistry {
    static let shared = ExtensionRegistry()
    
    // Built-in extensions
    var builtInExtensions: [ExtensionDescriptor] = []
    
    init() {
        populateBuiltIns()
    }
    
    func populateBuiltIns() {
        builtInExtensions = [
            // Media
            ExtensionDescriptor(
                id: "media",
                name: "Media",
                description: "Media controls, live activity, and music visualizer.",
                icon: "play.laptopcomputer",
                developer: "TheBoredTeam",
                version: "1.0.0",
                isBuiltIn: true,
                isEnabled: { @MainActor in
                    BoringViewCoordinator.shared.musicLiveActivityEnabled
                },
                setEnabled: { @MainActor newValue in
                    BoringViewCoordinator.shared.musicLiveActivityEnabled = newValue
                },
                supportedPoints: [.notchContent, .backgroundAmbient, .settings],
                contentProvider: { AnyExtensionContentProvider(MediaContentProvider()) }
            ),
            
            // Calendar
            ExtensionDescriptor(
                id: "calendar",
                name: "Calendar",
                description: "Show your next events and reminders.",
                icon: "calendar",
                developer: "TheBoredTeam",
                version: "1.0.0",
                isBuiltIn: true,
                isEnabled: { Defaults[.showCalendar] },
                setEnabled: { Defaults[.showCalendar] = $0 },
                supportedPoints: [.notchContent, .statusIndicators, .settings],
                contentProvider: { AnyExtensionContentProvider(CalendarContentProvider()) }
            ),
            
            // Battery
            ExtensionDescriptor(
                id: "battery",
                name: "Battery",
                description: "Monitor power status and battery percentage.",
                icon: "battery.100.bolt",
                developer: "TheBoredTeam",
                version: "1.0.0",
                isBuiltIn: true,
                isEnabled: { Defaults[.showBatteryIndicator] },
                setEnabled: { Defaults[.showBatteryIndicator] = $0 },
                supportedPoints: [.statusIndicators, .settings],
                contentProvider: { AnyExtensionContentProvider(BatteryContentProvider()) }
            ),
            
            // HUD
            ExtensionDescriptor(
                id: "hud",
                name: "HUD",
                description: "Replace system volume and brightness indicators.",
                icon: "dial.medium.fill",
                developer: "TheBoredTeam",
                version: "1.0.0",
                isBuiltIn: true,
                isEnabled: { Defaults[.hudReplacement] },
                setEnabled: { Defaults[.hudReplacement] = $0 },
                supportedPoints: [.hudOverlay, .settings],
                contentProvider: { AnyExtensionContentProvider(HUDContentProvider()) }
            ),
            
            // Shelf
            ExtensionDescriptor(
                id: "shelf",
                name: "Shelf",
                description: "Drag and drop area for temporary files.",
                icon: "books.vertical",
                developer: "TheBoredTeam",
                version: "1.0.0",
                isBuiltIn: true,
                isEnabled: { Defaults[.boringShelf] },
                setEnabled: { Defaults[.boringShelf] = $0 },
                supportedPoints: [.navigationTab, .settings],
                contentProvider: { AnyExtensionContentProvider(ShelfContentProvider()) },
                tabIcon: "books.vertical",
                tabTitle: "Shelf"
            ),
            
            // Camera Mirror
            ExtensionDescriptor(
                id: "camera",
                name: "Camera Mirror",
                description: "Preview yourself with your webcam in the notch.",
                icon: "camera.fill",
                developer: "TheBoredTeam",
                version: "1.0.0",
                isBuiltIn: true,
                isEnabled: { Defaults[.showMirror] },
                setEnabled: { Defaults[.showMirror] = $0 },
                supportedPoints: [.notchContent, .settings],
                contentProvider: { AnyExtensionContentProvider(CameraContentProvider()) }
            )
        ]
    }
}

