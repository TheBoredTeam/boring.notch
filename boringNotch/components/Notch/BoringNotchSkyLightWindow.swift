//
//  BoringNotchSkyLightWindow.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-20.
//

import Cocoa
import SkyLightWindow
import Defaults
import Combine

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
        
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }
        
        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

class BoringNotchSkyLightWindow: NSPanel {
    private static var allowsKeyboardFocus: Bool = false
    private static var shouldResetOnResign: Bool = true
    private var keyboardObserver: NSObjectProtocol?
    private var isSkyLightEnabled: Bool = false
    
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
        
        configureWindow()
        setupObservers()
        setupFocusHandling()
    }
    
    deinit {
        if let keyboardObserver {
            NotificationCenter.default.removeObserver(keyboardObserver)
        }
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false
        
        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        // Apply initial sharing type setting
        updateSharingType()
    }
    
    private func setupObservers() {
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
    }
    
    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
        }
    }
    
    private func setupFocusHandling() {
        // Allow becoming key when requested
        becomesKeyOnlyIfNeeded = false

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
                    // Let SwiftUI handle first responder
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
    
    private var observers: Set<AnyCancellable> = []
}
