//
//  BoringNotchWindow.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 06/08/24.
//

import Cocoa

class BoringNotchWindow: NSWindow {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        isOpaque = false
        alphaValue = 1
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        isReleasedWhenClosed = false
        level = .mainMenu + 1
        hasShadow = true
    }
    
    override var canBecomeKey: Bool {
        true
    }
    
    override var canBecomeMain: Bool {
        true
    }
}
