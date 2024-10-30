//
//  boringNotchApp.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import AVFoundation
import Combine
import KeyboardShortcuts
import Sparkle
import SwiftUI
import Defaults

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow
    let updaterController: SPUStandardUpdaterController
    let notchSpace = NotchSpaceManager.shared.notchSpace
    
    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    var body: some Scene {
        Settings {
            SettingsView(updaterController: updaterController)
                .environmentObject(appDelegate.vm)
        }
        
        Window("Onboarding", id: "onboarding") {
            ProOnboard()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        Window("Activation", id: "activation") {
            ActivationWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        MenuBarExtra("boring.notch", systemImage: "sparkle", isInserted: $showMenuBarIcon) {
            SettingsLink(label: {
                Text("Settings")
            })
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            if false {
                Button("Activate License") {
                    openWindow(id: "activation")
                }
            }
            CheckForUpdatesView(updater: updaterController.updater)
            Divider()
            Button("Restart Boring Notch") {
                    guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
                    
                    let workspace = NSWorkspace.shared
                    
                    if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                        
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.createsNewApplicationInstance = true
                        
                        workspace.openApplication(at: appURL, configuration: configuration)
                    }
                
                   NSApplication.shared.terminate(nil)
            }
            Button("Quit", role: .destructive) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var window: NSWindow!
    var sizing: Sizes = .init()
    let vm: BoringViewModel = .init()
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    let calenderManager = CalendarManager()
    private var previousScreens: [NSScreen]?
    @Environment(\.openWindow) var openWindow
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        
        vm.setupWorkersNotificationObservers();
    
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil) { [weak self] _ in
            self?.adjustWindowPosition(changeAlpha: true)
        }
        
        NotificationCenter.default.addObserver(forName: Notification.Name.notchHeightChanged, object: nil, queue: nil) { [weak self] _ in
            self?.adjustWindowPosition()
        }
        
        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            
            self.vm.toggleSneakPeek(
                status: !self.vm.sneakPeek.show,
                type: .music,
                duration: 3.0
            )
        }
        
        window = BoringNotchWindow(
            contentRect: NSRect(x: 0, y: 0, width: sizing.size.opened.width! + 20, height: sizing.size.opened.height! + 30),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = NSHostingView(rootView: ContentView(batteryModel: .init(vm: self.vm)).environmentObject(vm).environmentObject(MusicManager(vm: vm)!))
        
        adjustWindowPosition(changeAlpha: true)
        
        window.orderFrontRegardless()
        
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        
        if vm.firstLaunch {
            DispatchQueue.main.async {
                self.openWindow(id: "onboarding")
            }
            playWelcomeSound()
        }
    }
    
    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "boring", fileExtension: "m4a")
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
    
    @objc func screenConfigurationDidChange() {
        
        let currentScreens = NSScreen.screens
        guard currentScreens.count != previousScreens?.count else { return }
        previousScreens = currentScreens
        adjustWindowPosition(changeAlpha: true)
    }
    
    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if !NSScreen.screens.contains(where: {$0.localizedName == vm.selectedScreen}) {
            vm.selectedScreen = NSScreen.main?.localizedName ?? "Unknown"
        }
        
        let selectedScreen = NSScreen.screens.first(where: {$0.localizedName == vm.selectedScreen})
        closedNotchSize = setNotchSize(screen: selectedScreen?.localizedName)
        
        if let screenFrame = selectedScreen {
            window.alphaValue = changeAlpha ? 0 : 1
            window.makeKeyAndOrderFront(nil)
            
            DispatchQueue.main.async {[weak self] in
                self!.window.setFrameOrigin(screenFrame.frame.origin.applying(CGAffineTransform(translationX: (screenFrame.frame.width / 2) - self!.window.frame.width / 2, y: screenFrame.frame.height - self!.window.frame.height)))
                self!.window.alphaValue = 1
            }
        }
        //TODO: Improve animation here, especially for custom height slider
        if vm.notchState == .closed {
            vm.close()
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

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
}
