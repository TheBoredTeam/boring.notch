//
//  BoringViewCoordinator.swift
//  boringNotch
//
//  Created by Alexander on 2024-11-20.
//

import Combine
import Defaults
import SwiftUI
import TheBoringWorkerNotifier

enum SneakContentType {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
}

struct SharedSneakPeek: Codable {
    var show: Bool
    var type: String
    var value: String
    var icon: String
}

enum BrowserType {
    case chromium
    case safari
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
}

class BoringViewCoordinator: ObservableObject {
    static let shared = BoringViewCoordinator()
    var notifier: TheBoringWorkerNotifier = .init()
    
    @Published var currentView: NotchViews = .home
    private var sneakPeekDispatch: DispatchWorkItem?
    private var expandingViewDispatch: DispatchWorkItem?
    
    
    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true
    
    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if TrayDrop.shared.isEmpty || !Defaults[.openShelfByDefault] {
                    currentView = .home
                }
            }
        }
    }
    
    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }
    
    @AppStorage("hudReplacement") var hudReplacement: Bool = true {
        didSet {
            notifier.postNotification(name: notifier.toggleHudReplacementNotification.name, userInfo: nil)
        }
    }
    
    @AppStorage("preferred_screen_name") var preferredScreen = NSScreen.main?.localizedName ?? "Unknown" {
        didSet {
            selectedScreen = preferredScreen
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }
    
    @Published var selectedScreen: String = NSScreen.main?.localizedName ?? "Unknown"

    @Published var optionKeyPressed: Bool = true
    
    private init() {
        selectedScreen = preferredScreen
        notifier = TheBoringWorkerNotifier()
    }
    
    func setupWorkersNotificationObservers() {
            notifier.setupObserver(notification: notifier.micStatusNotification, handler: initialMicStatus)
            notifier.setupObserver(notification: notifier.sneakPeakNotification, handler: sneakPeekEvent)
        }
    
    @objc func sneakPeekEvent(_ notification: Notification) {
            let decoder = JSONDecoder()
            if let decodedData = try? decoder.decode(SharedSneakPeek.self, from: notification.userInfo?.first?.value as! Data) {
                let contentType = decodedData.type == "brightness" ? SneakContentType.brightness : decodedData.type == "volume" ? SneakContentType.volume : decodedData.type == "backlight" ? SneakContentType.backlight : decodedData.type == "mic" ? SneakContentType.mic : SneakContentType.brightness

                let value = CGFloat((NumberFormatter().number(from: decodedData.value) ?? 0.0).floatValue)
                let icon = decodedData.icon
                
                print(decodedData)
                
                toggleSneakPeek(status: decodedData.show, type: contentType, value: value, icon: icon)
                
            } else {
                print("Failed to decode JSON data")
            }
        }
    
    func toggleSneakPeek(status: Bool, type: SneakContentType, duration: TimeInterval = 1.5, value: CGFloat = 0, icon: String = "") {
        sneakPeekDuration = duration
        if type != .music {
            // close()
            if !hudReplacement {
                return
            }
        }
        DispatchQueue.main.async {
            withAnimation(.smooth) {
                self.sneakPeek.show = status
                self.sneakPeek.type = type
                self.sneakPeek.value = value
                self.sneakPeek.icon = icon
            }
        }

        if type == .mic {
            currentMicStatus = value == 1
        }
    }
    
    private var sneakPeekDuration: TimeInterval = 1.5
    
    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                sneakPeekDispatch?.cancel()

                sneakPeekDispatch = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    withAnimation {
                        self.toggleSneakPeek(status: false, type: SneakContentType.music)
                        self.sneakPeekDuration = 1.5
                    }
                }
                DispatchQueue.main
                    .asyncAfter(
                        deadline: .now() + self.sneakPeekDuration,
                        execute: sneakPeekDispatch!
                    )
            }
        }
    }
    
    func toggleExpandingView(status: Bool, type: SneakContentType, value: CGFloat = 0, browser: BrowserType = .chromium) {
        if expandingView.show {
            withAnimation(.smooth) {
                self.expandingView.show = false
            }
        }
        DispatchQueue.main.async {
            withAnimation(.smooth) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
                self.expandingView.browser = browser
            }
        }
    }
    
    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                expandingViewDispatch?.cancel()

                expandingViewDispatch = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.toggleExpandingView(status: false, type: SneakContentType.battery)
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + (expandingView.type == .download ? 2 : 3), execute: expandingViewDispatch!)
            }
        }
    }

    
    @objc func initialMicStatus(_ notification: Notification) {
        currentMicStatus = notification.userInfo?.first?.value as! Bool
    }
    
    func toggleMic() {
        notifier.postNotification(name: notifier.toggleMicNotification.name, userInfo: nil)
    }
    
    func showEmpty() {
        currentView = .home
    }
}
