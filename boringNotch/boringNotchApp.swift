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
        .defaultSize(CGSize(width: 750, height: 700))
        
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
    var window: NSWindow?
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
        cleanupWindows()
    }
    
    @objc func onScreenUnlocked(_: Notification) {
        print("Screen unlocked")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.cleanupWindows()
            self?.adjustWindowPosition(changeAlpha: true)
        }
    }
    
    private func cleanupWindows(shouldInvert: Bool = false) {
        if shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays] {
            for window in windows.values {
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            self.window = nil
        }
    }
    
    private func createBoringNotchWindow(for screen: NSScreen, with viewModel: BoringViewModel) -> NSWindow {
        let window = BoringNotchWindow(
            contentRect: NSRect(x: 0, y: 0, width: openNotchSize.width, height: openNotchSize.height),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = NSHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )
        
        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        return window
    }
    
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }
        
        DispatchQueue.main.async { [weak window] in
            guard let window = window else { return }
            let screenFrame = screen.frame
            window.setFrameOrigin(NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
            window.alphaValue = 1
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
        
        NotificationCenter.default.addObserver(forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            window.alphaValue = self.coordinator.selectedScreen == self.coordinator.preferredScreen ? 1 : 0
        }

        NotificationCenter.default.addObserver(forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            self.cleanupWindows(shouldInvert: true)
            
            if(!Defaults[.showOnAllDisplays]) {
                let viewModel = self.vm
                let window = self.createBoringNotchWindow(for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
                self.window = window
                self.adjustWindowPosition(changeAlpha: true)
            } else {
                self.adjustWindowPosition()
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
            
            var viewModel = self.vm
            
            if(Defaults[.showOnAllDisplays]) {
                for screen in NSScreen.screens {
                    if screen.frame.contains(mouseLocation) {
                        if let screenViewModel = self.viewModels[screen] {
                            viewModel = screenViewModel
                            break
                        }
                    }
                }
            }
            
            self.closeNotchWorkItem?.cancel()
            self.closeNotchWorkItem = nil
            
            switch viewModel.notchState {
            case .closed:
                viewModel.open()
                
                let workItem = DispatchWorkItem { [weak viewModel] in
                    viewModel?.close()
                }
                self.closeNotchWorkItem = workItem
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
            case .open:
                viewModel.close()
            }
        }
        
        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createBoringNotchWindow(for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }
        
        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.openWindow(id: "onboarding")
            }
            playWelcomeSound()
        }
        
        previousScreens = NSScreen.screens
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
            Set(currentScreens.map { $0.localizedName }) != Set(previousScreens?.map { $0.localizedName } ?? []) || 
            Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])
        
        previousScreens = currentScreens
        
        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition()
            }
        }
    }
    
    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreens = Set(NSScreen.screens)
            
            for screen in windows.keys where !currentScreens.contains(screen) {
                if let window = windows[screen] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    windows.removeValue(forKey: screen)
                    viewModels.removeValue(forKey: screen)
                }
            }
            
            for screen in currentScreens {
                if windows[screen] == nil {
                    let viewModel = BoringViewModel(screen: screen.localizedName)
                    let window = createBoringNotchWindow(for: screen, with: viewModel)
                    
                    windows[screen] = window
                    viewModels[screen] = viewModel
                }
                
                if let window = windows[screen], let viewModel = viewModels[screen] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)
                    
                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen
            
            if let preferredScreen = NSScreen.screens.first(where: { $0.localizedName == coordinator.preferredScreen }) {
                coordinator.selectedScreen = coordinator.preferredScreen
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main {
                coordinator.selectedScreen = mainScreen.localizedName
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }
            
            vm.screen = selectedScreen.localizedName
            vm.notchSize = getClosedNotchSize(screen: selectedScreen.localizedName)
            
            if window == nil {
                window = createBoringNotchWindow(for: selectedScreen, with: vm)
            }
            
            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)
                
                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }
    
    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }
    
    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    @objc func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}
