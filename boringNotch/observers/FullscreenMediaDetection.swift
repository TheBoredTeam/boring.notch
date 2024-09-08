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
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(self.applicationDidActivate(_:)),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil)
    }
    
    @objc func switchedToFullScreenApp(_ notification: Notification) {
        self.currentAppInFullScreen = true
    }
    
    @objc func applicationDidActivate(_ notification: Notification) {
        if self.nowPlaying.playing {
            NSLog(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
            
            self.currentAppInFullScreen = self.isFrontmostAppFullscreen(bundleIUn: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
            NSLog("currentAppInFullScreen: \(self.currentAppInFullScreen)")
        }
    }
    
    func isFrontmostAppFullscreen(bundleIUn: String) -> Bool {
        return !self.isMenuBarVisible()
    }
    
    func isMenuBarVisible() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) else {
            return false
        }
        
        for window in windows as NSArray {
            guard let winInfo = window as? NSDictionary else { continue }
            
            NSLog(
                "kCGWindowOwnerName: \(winInfo["kCGWindowOwnerName"] as? String ?? "")\n" +
                "kCGWindowName: \(winInfo["kCGWindowName"] as? String ?? "")"
            )
            
            
            if winInfo["kCGWindowOwnerName"] as? String == "Window Server" &&
                winInfo["kCGWindowName"] as? String == "Menubar"
            {
                
                return true
            }
        }
        
        return false
    }
}
