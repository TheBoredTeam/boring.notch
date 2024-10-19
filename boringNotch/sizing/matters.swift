    //
    //  sizeMatters.swift
    //  boringNotch
    //
    //  Created by Harsh Vardhan  Goswami  on 05/08/24.
    //

import SwiftUI
import Foundation

var closedNotchSize: CGSize = setNotchSize()

var downloadSneakSize: CGSize = .init(width: 65, height: 1)
var batterySenakSize: CGSize = .init(width: 160, height: 1)

func setNotchSize(screen: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = 32
    var notchWidth: CGFloat = 185
    
    var selectedScreen = NSScreen.main
    
    if let customScreen = screen {
        selectedScreen = NSScreen.screens.first(where: {$0.localizedName == customScreen})
    }
    
    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 10
        }
        
        // Use MenuBar height as notch height if there is no notch
        notchHeight = screen.frame.maxY - screen.visibleFrame.maxY + 10
        
        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            notchHeight = screen.safeAreaInsets.top
        }
    }
    
    return .init(width: notchWidth, height: notchHeight)
}

struct Area {
    var width: CGFloat?
    var height: CGFloat?
    var inset: CGFloat?
}

struct StatesSizes {
    var opened: Area
    var closed: Area
}

struct Sizes {
    var cornerRadius: StatesSizes = StatesSizes(opened: Area(inset: 24), closed: Area(inset: 10))
    var size: StatesSizes = StatesSizes(
        opened: Area(width: 580, height: 150),
        closed: Area(width: closedNotchSize.width, height: closedNotchSize.height)
    )
}

struct MusicPlayerElementSizes {
    
    var baseSize: Sizes = Sizes()
    
    var image: Sizes = Sizes(
        cornerRadius: StatesSizes(
            opened: Area(inset: 13), closed: Area(inset: 4)),
        size: StatesSizes(
            opened: Area(width: 90, height: 90), closed: Area(width: 20, height: 20)
        )
    )
    var player: Sizes = Sizes(
        size: StatesSizes(
            opened: Area(width: 440), closed: Area(width: closedNotchSize.width)
        )
    )
}
