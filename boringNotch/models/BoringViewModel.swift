//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import SwiftUI
import TheBoringWorkerNotifier
import Defaults

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!

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

class BoringViewModel: NSObject, ObservableObject {
    var cancellables: Set<AnyCancellable> = []

    let animationLibrary: BoringAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed
    @Published var currentView: NotchViews = .home
    @Published var headerTitle: String = "Glowing 🐼"
    @Published var emptyStateText: String = "Play some jams, ladies, and watch me shine! New features coming soon! 🎶 🚀"
    @Published var sizes: Sizes = .init()
    @Published var musicPlayerSizes: MusicPlayerElementSizes = .init()
    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @Published var whatsNewOnClose: (() -> Void)?
    @Published var notchMetastability: Bool = true // True if notch not open
    private var sneakPeekDispatch: DispatchWorkItem?
    private var expandingViewDispatch: DispatchWorkItem?
    @Published var showCHPanel: Bool = false
    @Published var optionKeyPressed: Bool = true
    @Published var showMusicLiveActivityOnClosed: Bool = true
    @Published var spacing: CGFloat = 16
    
    @Published var dragDetectorTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    
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
    
    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                sneakPeekDispatch?.cancel()

                sneakPeekDispatch = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    withAnimation {
                        self.togglesneakPeek(status: false, type: SneakContentType.music)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: sneakPeekDispatch!)
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

    @AppStorage("hudReplacement") var hudReplacement: Bool = true {
        didSet {
            toggleHudReplacement()
        }
    }

    @AppStorage("selected_screen_name") var selectedScreen = NSScreen.main?.localizedName ?? "Unknown" {
        didSet {
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true
    var notifier: TheBoringWorkerNotifier = .init()

    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    override
    init() {
        animation = animationLibrary.animation
        notifier = TheBoringWorkerNotifier()
        super.init()

        Publishers.CombineLatest($dropZoneTargeting, $dragDetectorTargeting)
            .map { value1, value2 in
                value1 || value2
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)
    }

    func open() {
        withAnimation(.bouncy) {
            self.notchSize = .init(width: Sizes().size.opened.width!, height: Sizes().size.opened.height!)
            self.notchMetastability = true
            self.notchState = .open
        }
    }

    func setupWorkersNotificationObservers() {
        notifier.setupObserver(notification: notifier.sneakPeekNotification, handler: sneakPeekEvent)

        notifier.setupObserver(notification: notifier.micStatusNotification, handler: initialMicStatus)
    }

    @objc func initialMicStatus(_ notification: Notification) {
        currentMicStatus = notification.userInfo?.first?.value as! Bool
    }

    @objc func sneakPeekEvent(_ notification: Notification) {
        let decoder = JSONDecoder()
        if let decodedData = try? decoder.decode(SharedSneakPeek.self, from: notification.userInfo?.first?.value as! Data) {
            let contentType = decodedData.type == "brightness" ? SneakContentType.brightness : decodedData.type == "volume" ? SneakContentType.volume : decodedData.type == "backlight" ? SneakContentType.backlight : decodedData.type == "mic" ? SneakContentType.mic : SneakContentType.brightness

            let value = CGFloat((NumberFormatter().number(from: decodedData.value) ?? 0.0).floatValue)
            let icon = decodedData.icon
            
            print(decodedData)
            
            togglesneakPeek(status: decodedData.show, type: contentType, value: value, icon: icon)
            
        } else {
            print("Failed to decode JSON data")
        }
    }

    @Published var notchSize: CGSize = .init(width: Sizes().size.closed.width!, height: Sizes().size.closed.height!)

    func toggleMusicLiveActivity(status: Bool) {
        withAnimation(.smooth) {
            self.showMusicLiveActivityOnClosed = status
        }
    }

    func toggleMic() {
        notifier.postNotification(name: notifier.toggleMicNotification.name, userInfo: nil)
    }
    
    func togglesneakPeek(status: Bool, type: SneakContentType, value: CGFloat = 0, icon: String = "") {
        if type != .music {
            close()
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

    func toggleHudReplacement() {
        notifier.postNotification(name: notifier.toggleHudReplacementNotification.name, userInfo: nil)
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

    func close() {
        withAnimation(.smooth) {
            self.notchSize = .init(width: Sizes().size.closed.width!, height: Sizes().size.closed.height!)
            self.notchState = .closed
            self.notchMetastability = false
        }

        // Set the current view to shelf if it contains files and the user enables openShelfByDefault
        // Otherwise, if the user has not enabled openLastShelfByDefault, set the view to home
        if !TrayDrop.shared.isEmpty && Defaults[.openShelfByDefault] {
            currentView = .shelf
        } else if !openLastTabByDefault {
            currentView = .home
        }
    }

    func openClipboard() {
        notifier.postNotification(name: notifier.showClipboardNotification.name, userInfo: nil)
    }

    func toggleClipboard() {
        openClipboard()
    }

    func showEmpty() {
        currentView = .home
    }

    func closeHello() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            self.firstLaunch = false
            withAnimation(self.animationLibrary.animation) {
                self.close()
            }
        }
    }
}
