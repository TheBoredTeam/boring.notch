//
//  AIAgentWindowController.swift
//  boringNotch
//
//  Hosts the full agent desktop window. Mirrors SettingsWindowController
//  but reuses the shared AIAgentViewModel for consistent state.
//

import AppKit
import SwiftUI

final class AIAgentWindowController: NSWindowController {
    static let shared = AIAgentWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
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
        guard let window else { return }
        window.title = "Boring Notch · Claude Code"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("BoringNotchAIAgentWindow")
        window.minSize = NSSize(width: 700, height: 460)

        let hostingView = NSHostingView(rootView: AIAgentFullView())
        window.contentView = hostingView
        window.delegate = self
    }

    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            window?.orderFrontRegardless()
            window?.makeKeyAndOrderFront(nil)
            return
        }
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    override func close() {
        super.close()
        relinquishFocus()
    }

    private func relinquishFocus() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
}

extension AIAgentWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        relinquishFocus()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}