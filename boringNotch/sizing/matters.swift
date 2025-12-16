//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20
let openNotchSize: CGSize = .init(width: 640, height: 190)
let windowSize: CGSize = .init(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil, hasLiveActivity: Bool = false) -> CGSize {
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            // In the notch height calculation section
            if Defaults[.useInactiveNotchHeight] && !hasLiveActivity {
                notchHeight = Defaults[.inactiveNotchHeight]
            } else {
                // existing height logic
                notchHeight = Defaults[.notchHeight]
                if Defaults[.notchHeightMode] == .matchRealNotchSize {
                    notchHeight = screen.safeAreaInsets.top
                } else if Defaults[.notchHeightMode] == .matchMenuBar {
                    notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
                }
            }
        } else {
            
            // If there's NO live activity and mode is custom, use the custom slider value
            if !hasLiveActivity && Defaults[.nonNotchHeightMode] == .custom {
                notchHeight = Defaults[.nonNotchHeight]
            }
            // If there IS live activity OR mode is not custom, use preset heights
            else if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            } else if Defaults[.nonNotchHeightMode] == .matchRealNotchSize {
                notchHeight = 32
            } else {
                notchHeight = 32
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}

@MainActor func getInactiveNotchSize(screenUUID: String? = nil) -> CGSize {
    let notchHeight: CGFloat = Defaults[.inactiveNotchHeight]
    var notchWidth: CGFloat = 185
    
    var selectedScreen = NSScreen.main
    
    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }
    }
    
    return .init(width: notchWidth, height: notchHeight)
}
