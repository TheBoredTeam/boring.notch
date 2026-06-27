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
    /// Remove the window from the SkyLight space.
    ///
    /// `delegateWindow` uses `SLSSpaceAddWindowsAndRemoveFromSpaces` (flag 7), which removes the
    /// window from ALL its current spaces — including the app's high-level `notchSpace` CGSSpace —
    /// and adds it to the SkyLight space. Undoing that here ONLY removes it from the SkyLight space;
    /// the window is then in no space. The caller (`disableSkyLight`) immediately re-homes it into
    /// `notchSpace` via `CGSSpace.reassert`, restoring the exact membership a fresh window has.
    ///
    /// We deliberately do NOT re-add the window to the active desktop space here: a normal-desktop
    /// 640×210 transparent panel sits in the regular hit-test stack and swallows desktop clicks
    /// across its margins. The high-level `notchSpace` is what isolates it from desktop hit-testing.
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        let windowList = [window.windowNumber] as CFArray

        if let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"), to: F_SLSRemoveWindowsFromSpaces?.self) {
            _ = SLSRemoveWindowsFromSpaces(connection, windowList, [space] as CFArray)
        }
    }
}

class BoringNotchSkyLightWindow: NSPanel {
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
            // 1. Remove from the SkyLight space (window is now in no space).
            SkyLightOperator.shared.undelegateWindow(self)
            // 2. Re-home into the app's high-level notchSpace — the exact CGS membership a fresh
            //    window has. This is what stops the transparent margins from swallowing desktop
            //    clicks after unlock. The notchSpace.windows Set still contains us (it was never
            //    mutated on lock), so a plain insert would be a didSet no-op; reassert forces the
            //    raw CGSAddWindowsToSpaces re-add. No window rebuild → no flash.
            NotchSpaceManager.shared.notchSpace.reassert([self])
            isSkyLightEnabled = false
        }
    }
    
    private var observers: Set<AnyCancellable> = []
    
    private func cleanupObservers() {
        Task { @MainActor in
            self.observers.forEach { $0.cancel() }
            self.observers.removeAll()
        }
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
