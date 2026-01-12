//
//  BoringNotchWindow.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 06/08/24.
//

import Cocoa

extension Notification.Name {
    static let boringNotchWindowKeyboardFocus = Notification.Name("BoringNotchWindowKeyboardFocus")
}

class BoringNotchWindow: NSPanel {
    private static var allowsKeyboardFocus: Bool = false
    private static var shouldResetOnResign: Bool = true
    private var keyboardObserver: NSObjectProtocol?

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
        becomesKeyOnlyIfNeeded = false  // Changed: allow becoming key when requested

        keyboardObserver = NotificationCenter.default.addObserver(
            forName: .boringNotchWindowKeyboardFocus,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let allow = notification.userInfo?["allow"] as? Bool ?? false
            
            if allow {
                // Set flag FIRST, then make key
                Self.allowsKeyboardFocus = true
                Self.shouldResetOnResign = false  // Don't reset when we're actively wanting focus
                
                // Force the window to become key
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    self.makeKeyAndOrderFront(nil)
                    self.makeFirstResponder(self.contentView)
                }
            } else {
                Self.shouldResetOnResign = true
                Self.allowsKeyboardFocus = false
                if self.isKeyWindow {
                    self.resignKey()
                }
            }
        }
    }

    deinit {
        if let keyboardObserver {
            NotificationCenter.default.removeObserver(keyboardObserver)
        }
    }

    override var canBecomeKey: Bool {
        Self.allowsKeyboardFocus
    }

    override var canBecomeMain: Bool {
        Self.allowsKeyboardFocus
    }

    override func resignKey() {
        super.resignKey()
        // Only reset if explicitly told to (not on natural focus loss)
        if Self.shouldResetOnResign {
            Self.allowsKeyboardFocus = false
        }
    }
}
