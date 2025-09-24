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
        becomesKeyOnlyIfNeeded = true

        keyboardObserver = NotificationCenter.default.addObserver(
            forName: .boringNotchWindowKeyboardFocus,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let allow = notification.userInfo?["allow"] as? Bool ?? false
            Self.allowsKeyboardFocus = allow
            if allow {
                if !self.isKeyWindow {
                    NSApp.activate(ignoringOtherApps: true)
                    self.makeKeyAndOrderFront(nil)
                }
            } else {
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
        Self.allowsKeyboardFocus = false
    }
}
