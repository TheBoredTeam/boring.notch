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
    @AppStorage("showMenuBarIcon") var showMenuBarIcon: Bool = true
    
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.vm)
        }
        
        MenuBarExtra("boring.notch", systemImage: "music.note", isInserted: $showMenuBarIcon) {
            Button("Check for updates") {
            }
            .keyboardShortcut(KeyEquivalent("U"), modifiers: .command)
            .disabled(true)
            Divider()
            Button("Quit", role: .destructive) {
                exit(0)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var window: NSWindow!
    var sizing: Sizes = Sizes()
    let vm: BoringViewModel = BoringViewModel()
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(adjustWindowPosition),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        
        window = BoringNotchWindow(
            contentRect: NSRect(x: 0, y: 0, width: sizing.size.opened.width!, height: sizing.size.opened.height!), styleMask: [.borderless], backing: .buffered, defer: false
        )
        
        window.contentView = NSHostingView(rootView: ContentView(onHover: adjustWindowPosition, batteryModel: .init(vm: self.vm)).environmentObject(vm))
        
        // Set the initial window position
        adjustWindowPosition()
        
        window.orderFrontRegardless()
    }
    
    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }
    
    
    @objc func adjustWindowPosition() {
        if let screenFrame = NSScreen.main?.frame {
            let windowWidth = window.frame.width
            let windowHeight = window.frame.height
            let notchCenterX = screenFrame.width / 2
            let statusBarHeight: CGFloat = 17
            let windowX = notchCenterX - windowWidth / 2
            let windowY = screenFrame.height - statusBarHeight - windowHeight / 2
            
            window.setFrame(NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight), display: true)
        }
    }
    
    
    @objc func togglePopover(_ sender: Any?) {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }
    
    @objc func showMenu() {
        statusItem!.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    @objc func quitAction() {
        NSApplication.shared.terminate(nil)
    }
    
    
    
}
