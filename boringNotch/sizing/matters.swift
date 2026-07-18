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

// Horizontal gap between closed-state live-activity content (album art / waveform)
// and the physical notch edge. Without this margin the hardware bezel clips the
// adjacent content since the spacer rect used to be narrower than the physical notch.
let liveActivityEdgeMargin: CGFloat = 8

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

@MainActor private func defaultMenuBarHeight(hasNotch: Bool) -> CGFloat {
    if #available(macOS 26.0, *) {
        return hasNotch ? 38 : 29
    }

    return hasNotch ? 43 : 23
}

@MainActor private func resolvedMenuBarHeight(for screen: NSScreen?) -> CGFloat {
    if let screen {
        let measuredHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY - 1)
        if measuredHeight > 0 {
            return measuredHeight
        }

        return defaultMenuBarHeight(hasNotch: screen.safeAreaInsets.top > 0)
    }

    return defaultMenuBarHeight(hasNotch: false)
}

@MainActor func getMenuBarHeight(for screen: NSScreen?) -> CGFloat {
    resolvedMenuBarHeight(for: screen ?? NSScreen.main ?? NSScreen.screens.first)
}

@MainActor func getMenuBarHeight(hasNotch: Bool) -> CGFloat {
    if let matchingScreen = NSScreen.screens.first(where: { ($0.safeAreaInsets.top > 0) == hasNotch }) {
        return resolvedMenuBarHeight(for: matchingScreen)
    }

    return defaultMenuBarHeight(hasNotch: hasNotch)
}

@MainActor func syncNotchHeightIfNeeded() {
    var didChangeHeight = false

    switch Defaults[.notchHeightMode] {
    case .matchRealNotchSize:
        let realHeight = getRealNotchHeight()
        if Defaults[.notchHeight] != realHeight {
            Defaults[.notchHeight] = realHeight
            didChangeHeight = true
        }

    case .matchMenuBar:
        let menuHeight = getMenuBarHeight(hasNotch: true)
        if Defaults[.notchHeight] != menuHeight {
            Defaults[.notchHeight] = menuHeight
            didChangeHeight = true
        }

    case .custom:
        break
    }

    switch Defaults[.nonNotchHeightMode] {
    case .matchMenuBar:
        let menuHeight = getMenuBarHeight(hasNotch: false)
        if Defaults[.nonNotchHeight] != menuHeight {
            Defaults[.nonNotchHeight] = menuHeight
            didChangeHeight = true
        }

    case .matchRealNotchSize, .custom:
        break
    }

    if didChangeHeight {
        NotificationCenter.default.post(name: .notchHeightChanged, object: nil)
    }
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
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
        notchHeight = screen.safeAreaInsets.top > 0 ? Defaults[.notchHeight] : Defaults[.nonNotchHeight]
    }

    return .init(width: notchWidth, height: notchHeight)
}
