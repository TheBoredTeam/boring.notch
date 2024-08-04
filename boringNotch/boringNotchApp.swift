//
//  boringNotchApp.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var window: NSWindow!
    
    
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "BoringNotch")
            button.action = #selector(showMenu)
        }
        
        // Set up the menu
        let menu = NSMenu()
//        menu.addItem(NSMenuItem(title: "Play/Pause", action: #selector(playPauseAction), keyEquivalent: "p"))
//        menu.addItem(NSMenuItem(title: "Next Track", action: #selector(nextTrackAction), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q"))
        statusItem?.menu = menu
        
        
        // Create the window content
        let contentView = ContentView(onHover: adjustWindowPosition, vm: .init(), batteryModel: .init())
        
        // Initialize the window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: contentView)
        
        // Set the initial window position
        adjustWindowPosition()
        
        window.orderFrontRegardless()
    }
    
    func adjustWindowPosition() {
        if let screenFrame = NSScreen.main?.frame {
            let windowWidth = window.frame.width
            let windowHeight = window.frame.height
            let notchCenterX = screenFrame.width / 2
            let statusBarHeight: CGFloat = 20
            let windowX = notchCenterX - windowWidth / 2
            let windowY = screenFrame.height - statusBarHeight - windowHeight / 2
            
            window.setFrame(NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight), display: true)
        }
    }
    
    
    @objc func playPauseAction() {
        // Implement play/pause action
    }
    
    @objc func nextTrackAction() {
        // Implement next track action
    }
    
    @objc func quitAction() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    @objc func togglePopover(_ sender: Any?) {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }
}
