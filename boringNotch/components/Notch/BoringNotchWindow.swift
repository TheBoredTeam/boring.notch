//
//  BoringNotchWindow.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 06/08/24.
//

import Cocoa

class BoringNotchWindow: NSPanel {
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
        
        isFloatingPanel = true
        isOpaque = false
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
        level = .mainMenu + 3
        hasShadow = false

        // Become key only when a control actually needs it (e.g. routing a
        // Finder drag session). Ordinary clicks are delivered straight to the
        // views WITHOUT the panel grabbing key focus — which is what lets
        // Cmd/Shift multi-select in the Shelf work again. Without this, the
        // first click on the panel is consumed as a key-grab.
        becomesKeyOnlyIfNeeded = true
    }

    // Eligible to become key so macOS routes Finder drag sessions here
    // (required for Shelf drag-and-drop). As a .nonactivatingPanel this does
    // not activate the app or steal Dock focus.
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
