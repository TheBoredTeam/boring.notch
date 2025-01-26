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
    
    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    var body: some Scene {
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
        
        Settings {
            SettingsView(updaterController: updaterController)
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
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [NSScreen: NSWindow] = [:]
    var viewModels: [NSScreen: BoringViewModel] = [:]
    var window: NSWindow!
    let vm: BoringViewModel = .init()
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    let calenderManager = CalendarManager()
    var closeNotchWorkItem: DispatchWorkItem?
    private var previousScreens: [NSScreen]?
    @Environment(\.openWindow) var openWindow
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func onScreenLocked(_: Notification) {
        print("Screen locked")
        // Clean up windows when screen locks
        cleanupWindows()
    }
    
    @objc func onScreenUnlocked(_: Notification) {
        print("Screen unlocked")
        // Reset and readjust windows when screen unlocks
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.cleanupWindows()
            self?.adjustWindowPosition()
        }
    }
    
    private func cleanupWindows() {
        // Close and remove all existing windows
        if Defaults[.showOnAllDisplays] {
            for window in windows.values {
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        coordinator.setupWorkersNotificationObservers();
    
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

        NotificationCenter.default.addObserver(forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil) { [weak self] _ in
            if(!Defaults[.showOnAllDisplays]) {
                self?.window = BoringNotchWindow(
                    contentRect: NSRect(x: 0, y: 0, width: openNotchSize.width, height: openNotchSize.height),
                    styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
                    backing: .buffered,
                    defer: false
                )

                if let windowValues = self?.windows.values {
                    for window in windowValues {
                        window.close()
                    }
                }

                self?.window.contentView = NSHostingView(rootView: ContentView(batteryModel: .init(vm: self!.vm)).environmentObject(self!.vm).environmentObject(MusicManager(vm: self!.vm)!))

                self?.adjustWindowPosition(changeAlpha: true)

                self?.window.orderFrontRegardless()

                NotchSpaceManager.shared.notchSpace.windows.insert(self!.window)
            } else {
                self?.window.close()
                self?.windows = [:]
                self?.adjustWindowPosition()
            }
        }

        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onScreenLocked(_:)), name: NSNotification.Name(rawValue: "com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onScreenUnlocked(_:)), name: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"), object: nil)

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }

            self.coordinator.toggleSneakPeek(
                status: !self.coordinator.sneakPeek.show,
                type: .music,
                duration: 3.0
            )
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            guard let self = self else { return }
            
            let mouseLocation = NSEvent.mouseLocation
            
            var viewModel = self.vm;
            
            if(Defaults[.showOnAllDisplays]) {
                for screen in NSScreen.screens {
                    if screen.frame.contains(mouseLocation) {
                        viewModel = viewModels[screen] ?? viewModel
                    }
                }
            }
            switch viewModel.notchState {
            case .closed:
                viewModel.open()
                self.closeNotchWorkItem?.cancel()
                
                let workItem = DispatchWorkItem {
                    viewModel.close()
                }
                self.closeNotchWorkItem = workItem
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
            case .open:
                self.closeNotchWorkItem?.cancel()
                self.closeNotchWorkItem = nil
                viewModel.close()
            }
        }
        
        if !Defaults[.showOnAllDisplays] {
            window = BoringNotchWindow(
                contentRect: NSRect(x: 0, y: 0, width: openNotchSize.width, height: openNotchSize.height),
                styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
                backing: .buffered,
                defer: false
            )
            
            window.contentView = NSHostingView(rootView: ContentView(batteryModel: .init(vm: self.vm)).environmentObject(vm).environmentObject(MusicManager(vm: vm)!))
            
            adjustWindowPosition(changeAlpha: true)
            
            window.orderFrontRegardless()
            
            NotchSpaceManager.shared.notchSpace.windows.insert(window)
        } else {
            adjustWindowPosition()
        }
        
        if coordinator.firstLaunch {
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
        let screensChanged = currentScreens.count != previousScreens?.count || 
            Set(currentScreens.map { $0.localizedName }) != Set(previousScreens?.map { $0.localizedName } ?? [])
        
        if screensChanged {
            previousScreens = currentScreens
            cleanupWindows()
            adjustWindowPosition()
        }
    }
    
    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                if windows[screen] == nil {
                    let viewModel: BoringViewModel = .init(screen: screen.localizedName)
                    let window = BoringNotchWindow(
                        contentRect: NSRect(x: 0, y: 0, width: openNotchSize.width, height: openNotchSize.height),
                        styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
                        backing: .buffered,
                        defer: false
                    )
                    window.contentView = NSHostingView(
                        rootView: ContentView(batteryModel: .init(vm: viewModel))
                            .environmentObject(viewModel)
                            .environmentObject(MusicManager(vm: viewModel)!)
                    )
                    windows[screen] = window
                    viewModels[screen] = viewModel
                    window.orderFrontRegardless()
                    NotchSpaceManager.shared.notchSpace.windows.insert(window)
                }
                if let window = windows[screen] {
                    window.alphaValue = changeAlpha ? 0 : 1
                    DispatchQueue.main.async {
                        let screenFrame = screen.frame
                        window.setFrameOrigin(NSPoint(
                            x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                            y: screenFrame.origin.y + screenFrame.height - window.frame.height
                        ))
                        window.alphaValue = 1
                    }
                }
                if let viewModel = viewModels[screen] {
                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            if !NSScreen.screens.contains(where: {$0.localizedName == coordinator.preferredScreen}) {
                coordinator.selectedScreen = NSScreen.main?.localizedName ?? "Unknown"
            }
            
            let selectedScreen = NSScreen.screens.first(where: {$0.localizedName == coordinator.selectedScreen})
            vm.notchSize = getClosedNotchSize(screen: selectedScreen?.localizedName)
     
            if let screenFrame = selectedScreen {
                window.alphaValue = changeAlpha ? 0 : 1
                window.makeKeyAndOrderFront(nil)

                DispatchQueue.main.async {[weak self] in
                    guard let self = self else { return }
                    let origin = NSPoint(
                        x: screenFrame.frame.origin.x + (screenFrame.frame.width / 2) - self.window.frame.width / 2,
                        y: screenFrame.frame.origin.y + screenFrame.frame.height - self.window.frame.height
                    )
                    self.window.setFrameOrigin(origin)
                    self.window.alphaValue = 1
                }
            }
            if vm.notchState == .closed {
                vm.close()
            }
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
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
}
