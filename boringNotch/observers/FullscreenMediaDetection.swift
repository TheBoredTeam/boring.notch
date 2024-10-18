//
//  FullscreenMediaDetection.swift
//  boringNotch
//
//  Created by Richard Kunkli on 06/09/2024.
//

import Accessibility
import Cocoa
import CoreAudio
import SwiftUI

class FullscreenMediaDetector: ObservableObject {
    @Published var currentAppInFullScreen: Bool = false {
        didSet {
            self.objectWillChange.send()
        }
    }
    
    var nowPlaying: NowPlaying = .init()
    
    init() {
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        let notifications: [(Notification.Name, Selector)] = [
            (NSWorkspace.activeSpaceDidChangeNotification, #selector(activeSpaceDidChange(_:))),
            (NSApplication.didChangeScreenParametersNotification, #selector(applicationDidChangeScreenMode(_:))),
            (NSWorkspace.didActivateApplicationNotification, #selector(applicationDidChangeScreenMode(_:)))
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
                self.currentAppInFullScreen = self.isAppFullScreen(frontmostApp)
                self.logFullScreenStatus(frontmostApp)
            }
        }
    }
    
    private func logFullScreenStatus(_ app: NSRunningApplication) {
        NSLog("Current app in full screen: \(currentAppInFullScreen)")
        NSLog("App name: \(app.localizedName ?? "Unknown")")
    }
    
    func isAppFullScreen(_ app: NSRunningApplication) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        let appWindows = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier }
        
        return appWindows.contains { window in
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let isOnScreen = window[kCGWindowIsOnscreen as String] as? Bool,
                  isOnScreen else {
                return false
            }
            
            
            
            let windowFrame = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            
            return NSScreen.screens.contains { screen in
                let isFullScreen = windowFrame.equalTo(screen.frame)
                
                let isSafariFullScreen = windowFrame.size.width == screen.frame.size.width
                
                return isFullScreen || app.localizedName == "Safari" && isSafariFullScreen
            }
        }
    }
}
