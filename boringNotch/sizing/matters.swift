//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import SwiftUI
import Foundation

var closedNotchSize: CGSize = setNotchSize()

func setNotchSize() -> CGSize {
    
    var notchHeight: CGFloat = 32
    var notchWidth: CGFloat = 185
    
    // Check if the screen is available
    if let screen = NSScreen.main {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 10
        }
        
        // Use MenuBar height as notch height if there is no notch
        notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
        
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
    var corderRadius: StatesSizes = StatesSizes(opened: Area(inset: 24), closed: Area(inset:10))
    var size: StatesSizes = StatesSizes(
        opened: Area(width: 500, height: 130),
        closed: Area(width: closedNotchSize.width, height: closedNotchSize.height)
    )
}

struct MusicPlayerElementSizes {
    
    var baseSize: Sizes = Sizes()
    
    var image: Sizes = Sizes(
        corderRadius: StatesSizes(
            opened: Area(inset: 14), closed: Area(inset:4)),
        size: StatesSizes(
            opened: Area(width: 70, height: 70), closed: Area(width: 20, height: 20)
        )
    )
    var player: Sizes = Sizes(
        size: StatesSizes(
            opened: Area(width: 430), closed: Area(width: closedNotchSize.width)
        )
    )
}
