//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

// Default notch size, to avoid using optionals
var notchHeight: CGFloat = Defaults[.nonNotchHeight]
var notchWidth: CGFloat = 185
var hasNotch: Bool = false // Added global hasNotch variable

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

@MainActor func getRealNotchHeight() -> CGFloat {
    for screen in NSScreen.screens {
        let safeAreaTop = screen.safeAreaInsets.top
        if safeAreaTop > 0 {
            return safeAreaTop
        }
    }
    
    return 38
}

@MainActor func getMenuBarHeight() -> CGFloat {
    for screen in NSScreen.screens {
        if screen.safeAreaInsets.top > 0 {
            return screen.frame.maxY - screen.visibleFrame.maxY - 1
        }
    }

    return 43
}

@MainActor func syncNotchHeightIfNeeded() {
    switch Defaults[.notchHeightMode] {
    case .matchRealNotchSize:
        let realHeight = getRealNotchHeight()
        if Defaults[.notchHeight] != realHeight {
            Defaults[.notchHeight] = realHeight
            NotificationCenter.default.post(name: .notchHeightChanged, object: nil)
        }

    case .matchMenuBar:
        let menuHeight = getMenuBarHeight()
        if Defaults[.notchHeight] != menuHeight {
            Defaults[.notchHeight] = menuHeight
            NotificationCenter.default.post(name: .notchHeightChanged, object: nil)
        }

    case .custom:
        break
    }
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {

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
        notchHeight = screen.safeAreaInsets.top > 0 ? Defaults[.notchHeight] : Defaults[.nonNotchHeight]
    }

    return .init(width: notchWidth, height: notchHeight)
}
