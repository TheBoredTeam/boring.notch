//
//  FullscreenMediaDetection.swift
//  boringNotch
//
//  Created by Richard Kunkli on 06/09/2024.
//

import Accessibility
import Cocoa
import CoreAudio
import Defaults
import MacroVisionKit
import SwiftUI

class FullscreenMediaDetector: ObservableObject {
    let detector: MacroVisionKit
    @Published var currentAppInFullScreen: Bool = false {
        didSet {
            objectWillChange.send()
        }
    }
    
    var nowPlaying: NowPlaying = .init()
    
    init() {
        self.detector = MacroVisionKit.shared
        detector.configuration.includeSystemApps = true
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        let notifications: [(Notification.Name, Selector)] = [
            (NSWorkspace.activeSpaceDidChangeNotification, #selector(activeSpaceDidChange(_:))),
            (NSApplication.didChangeScreenParametersNotification, #selector(applicationDidChangeScreenMode(_:))),
            (NSWorkspace.didActivateApplicationNotification, #selector(applicationDidChangeScreenMode(_:))),
            (NSWorkspace.didDeactivateApplicationNotification, #selector(applicationDidChangeScreenMode(_:))), // Listen for when an application is deactivated
            (NSApplication.didBecomeActiveNotification, #selector(applicationDidChangeScreenMode(_:))), // Listen for when the application becomes active
            (NSApplication.didResignActiveNotification, #selector(applicationDidChangeScreenMode(_:))) // Listen for when the application resigns active status
        ]
        
        for (name, selector) in notifications {
            notificationCenter.addObserver(self, selector: selector, name: name, object: nil)
        }
    }
    
    @objc func activeSpaceDidChange(_ notification: Notification) {
        checkFullScreenStatus()
    }
    
    @objc func applicationDidChangeScreenMode(_ notification: Notification) {
        checkFullScreenStatus()
    }
    
    func checkFullScreenStatus() {
        DispatchQueue.main.async {
            if let frontmostApp = NSWorkspace.shared.frontmostApplication {
                // Exclude Finder
                guard frontmostApp.bundleIdentifier != "com.apple.finder" else {
                    self.currentAppInFullScreen = false
                    return
                }
                
                let sameAsNowPlaying = !Defaults[.alwaysHideInFullscreen] ? frontmostApp.bundleIdentifier == self.nowPlaying.appBundleIdentifier : true
                
                NSLog(Defaults[.enableFullscreenMediaDetection] ? "Fullscreen media detection is enabled." : "Fullscreen media detection is disabled.")
                NSLog("Determine if app is in fullscreen: \(String(describing: sameAsNowPlaying))")
                
                self.currentAppInFullScreen = self.isAppFullScreen(frontmostApp) && sameAsNowPlaying
            }
        }
    }
    
    func isAppFullScreen(_ app: NSRunningApplication) -> Bool {
        let fullscreenApps = detector.detectFullscreenApps(debug: false)
        return fullscreenApps.contains {
            // Exclude Finder
            guard $0.bundleIdentifier != "com.apple.finder" else { return false }
            
            let isSameApp = $0.bundleIdentifier == app.bundleIdentifier
            if isSameApp { NSLog("Same app found! (Fullscreen: \(String(describing: $0.debugDescription)))") }
            return isSameApp
        }
    }
}
