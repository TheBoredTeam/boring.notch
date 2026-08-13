//
//  SettingsWindowController.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-14.
//

import AppKit
import SwiftUI
import Defaults

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        window.title = "蛋神设置"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        
        // Make it behave like a regular app window with proper Spaces support
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        
        // Ensure proper window behavior
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        window.level = .normal
        
        // Configure window to be a standard document-style window
        window.isRestorable = true
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("DanShenSettingsWindow")
        
        // Create the SwiftUI content
        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView
        
        // Handle window closing
        window.delegate = self
    }
    
    func showWindow() {
        guard let window else { return }
        let shouldCenter = !window.isVisible

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppWindowPresentationCoordinator.shared.present(window)

        if shouldCenter {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }
    
    override func close() {
        super.close()
    }
    
    private func relinquishFocus() {
        guard let window else { return }
        AppWindowPresentationCoordinator.shared.dismiss(window)
        AppWindowPresentationCoordinator.shared.relinquishApplicationFocusIfPossible()
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        relinquishFocus()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let window {
            AppWindowPresentationCoordinator.shared.present(window)
        }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        AppWindowPresentationCoordinator.shared.refresh()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        if let window {
            AppWindowPresentationCoordinator.shared.present(window)
        }
    }
    
    func windowDidResignKey(_ notification: Notification) {
    }
    
}
