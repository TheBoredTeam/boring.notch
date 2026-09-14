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
import SwiftUI

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
    private var isSkyLightEnabled: Bool = false
    private(set) var interactionRect: CGRect = .zero
    private var pointerMonitor: Any?
    private var localPointerMonitor: Any?

    func updateInteractionRect(_ rect: CGRect) {
        interactionRect = rect
        updatePointerAcceptance()
    }

    private func updatePointerAcceptance() {
        ignoresMouseEvents = !acceptsPointer(atScreenPoint: NSEvent.mouseLocation)
    }

    func acceptsPointer(atScreenPoint point: CGPoint) -> Bool {
        interactionRect.contains(convertPoint(fromScreen: point))
    }

    private func startPointerMonitoring() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.updatePointerAcceptance()
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.updatePointerAcceptance()
            return event
        }
    }

    private func stopPointerMonitoring() {
        [pointerMonitor, localPointerMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        pointerMonitor = nil
        localPointerMonitor = nil
    }

    
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
        startPointerMonitoring()
        ignoresMouseEvents = true
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
        
        updateCollectionBehavior()
        
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
            
        Defaults.publisher(.hideNonNotchedFromMissionControl)
            .sink { [weak self] _ in
                self?.updateCollectionBehavior()
            }
            .store(in: &observers)
            
        NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification, object: self)
            .sink { [weak self] _ in
                self?.updateCollectionBehavior()
            }
            .store(in: &observers)
        
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: self)
            .sink { [weak self] _ in
                self?.cleanupObservers()
            }
            .store(in: &observers)
    }
    
    private func updateCollectionBehavior() {
        var newBehavior: NSWindow.CollectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        let hasNotch = (self.screen?.safeAreaInsets.top ?? 0) > 0
        
        if Defaults[.hideNonNotchedFromMissionControl] && !hasNotch {
            newBehavior.insert(.transient)
        }
        
        collectionBehavior = newBehavior
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
    
    private var observers: Set<AnyCancellable> = []
    
    private func cleanupObservers() {
        stopPointerMonitoring()
        Task { @MainActor in
            self.observers.forEach { $0.cancel() }
            self.observers.removeAll()
        }
    }
    
    /// False by default so a click on the notch never activates the app or
    /// steals focus from whatever is frontmost — load-bearing for every
    /// normal interaction (hover-to-open, music controls, OSD). A text field
    /// needs this flipped on for the moment it's actually being typed into,
    /// and back off the instant it isn't — never left permanently true.
    ///
    /// This is the window class actually instantiated for the notch
    /// (createBoringNotchWindow uses BoringNotchSkyLightWindow, not the
    /// separate, unused BoringNotchWindow class) — an earlier fix targeted
    /// that unused class and silently did nothing.
    var wantsKeyForTextInput = false {
        didSet {
            guard wantsKeyForTextInput != oldValue else { return }
            if wantsKeyForTextInput {
                makeKey()
            }
        }
    }

    override var canBecomeKey: Bool { wantsKeyForTextInput }
    override var canBecomeMain: Bool { false }
}

/// Reports the actual SwiftUI layout in window coordinates. Returning nil from
/// this view's hitTest alone would not pass clicks through an NSWindow, so the
/// panel also updates ignoresMouseEvents while the pointer is outside the region.
struct NotchInteractionRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> RegionView { RegionView() }
    func updateNSView(_ nsView: RegionView, context: Context) { nsView.report() }

    final class RegionView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report() }
        override func layout() { super.layout(); report() }
        override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); report() }
        override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); report() }
        func report() {
            guard !bounds.isEmpty, let panel = window as? BoringNotchSkyLightWindow else { return }
            panel.updateInteractionRect(convert(bounds, to: nil))
        }
    }
}
