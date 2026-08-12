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
    }
    
    /// False by default so a click on the notch never steals focus from
    /// whatever app is frontmost — that's load-bearing for every other
    /// interaction (hover-to-open, music controls, OSD). But it also means
    /// NO text field in this window can ever receive a keystroke: SwiftUI's
    /// @FocusState/.focused() only sets the responder *within* the view
    /// hierarchy, and macOS never routes real keyDown events to a window
    /// that can't become key. A reply field needs this flipped on for the
    /// moment it's actually being typed into, and back off immediately
    /// after — never left permanently true, or every other interaction
    /// regresses.
    var wantsKeyForTextInput = false {
        didSet {
            guard wantsKeyForTextInput != oldValue else { return }
            if wantsKeyForTextInput {
                makeKey()
            }
        }
    }

    override var canBecomeKey: Bool {
        wantsKeyForTextInput
    }

    override var canBecomeMain: Bool {
        false
    }
}
