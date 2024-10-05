//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import SwiftUI
import TheBoringWorkerNotifier

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

struct SneakPeak {
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
    @Published var waitInterval: Double = 3
    @Published var releaseName: String = "Glowing Panda 🐼 (Snooty)"
    @Published var coloredSpectrogram: Bool = true
    @Published var accentColor: Color = .accentColor
    @Published var selectedDownloadIndicatorStyle: DownloadIndicatorStyle = .progress
    @Published var selectedDownloadIconStyle: DownloadIconStyle = .onlyAppIcon
    @AppStorage("showMenuBarIcon") var showMenuBarIcon: Bool = true
    @Published var enableHaptics: Bool = true
    @Published var nothumanface: Bool = false
    @Published var showBattery: Bool = true
    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @Published var showChargingInfo: Bool = true
    @Published var chargingInfoAllowed: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @Published var whatsNewOnClose: (() -> Void)?
    @Published var minimumHoverDuration: TimeInterval = 0.3
    @Published var notchMetastability: Bool = true // True if notch not open
    @Published var settingsIconInNotch: Bool = false
    @Published var openNotchOnHover: Bool = true // TODO: Change this
    private var sneakPeakDispatch: DispatchWorkItem?
    private var expandingViewDispatch: DispatchWorkItem?
    @Published var enableSneakPeek: Bool = true
    @Published var showCHPanel: Bool = false
    @Published var systemEventIndicatorShadow: Bool = false
    @Published var systemEventIndicatorUseAccent: Bool = false
    @Published var clipboardHistoryHideScrollbar: Bool = true
    @Published var clipboardHistoryPreserveScrollPosition: Bool = false
    @Published var optionKeyPressed: Bool = true
    @Published var spacing: CGFloat = 16
    @Published var boringShelf: Bool = true
    @Published var showMusicLiveActivityOnClosed: Bool = true

    @Published var dragDetectorTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false

    @Published var anyDropZoneTargeting: Bool = false

    @Published var clipboardHistoryAlwaysShowIcons: Bool = true
    @Published var clipboardHistoryAutoFocusSearch: Bool = false
    @Published var clipboardHistoryCloseAfterCopy: Bool = false
    @Published var showEmojis: Bool = false
    @Published var clipboardHistoryVisibleTilesCount: CGFloat = 5
    @Published var sneakPeak: SneakPeak = .init() {
        didSet {
            if sneakPeak.show {
                sneakPeakDispatch?.cancel()

                sneakPeakDispatch = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    withAnimation {
                        self.toggleSneakPeak(status: false, type: SneakContentType.music)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: sneakPeakDispatch!)
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

    @Published var maxClipboardRecords: Int = 1000
    @Published var sizeOfClipbordCache: String = "0 MB"
    @Published var showMirror: Bool = false
    @Published var mirrorShape: MirrorShapeEnum = .rectangle
    @Published var tilesShowLabels: Bool = false
    @Published var gestureSensitivity: CGFloat = 200
    @Published var closeGestureEnabled: Bool = true
    @Published var cornerRadiusScaling: Bool = true
    @Published var openShelfByDefault: Bool = true
    @Published var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }
    @Published var enableShadow: Bool = true
    @Published var enableGestures: Bool = true
    @Published var enableGradient: Bool = false
    @Published var alwaysShowTabs: Bool = false {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if TrayDrop.shared.isEmpty || !openShelfByDefault {
                    currentView = .home
                }
            }
        }
    }
    @Published var enableFullscreenMediaDetection: Bool = true
    @Published var inlineHUD: Bool = true

    @AppStorage("enableDownloadListener") var enableDownloadListener: Bool = false {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("enableDownloadListener") var enableSafariDownloads: Bool = false {
        didSet {}
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
        notifier.setupObserver(notification: notifier.sneakPeakNotification, handler: sneakPeakEvent)

        notifier.setupObserver(notification: notifier.micStatusNotification, handler: initialMicStatus)
    }

    @objc func initialMicStatus(_ notification: Notification) {
        currentMicStatus = notification.userInfo?.first?.value as! Bool
    }

    @objc func sneakPeakEvent(_ notification: Notification) {
        let decoder = JSONDecoder()
        if let decodedData = try? decoder.decode(SharedSneakPeek.self, from: notification.userInfo?.first?.value as! Data) {
            let contentType = decodedData.type == "brightness" ? SneakContentType.brightness : decodedData.type == "volume" ? SneakContentType.volume : decodedData.type == "backlight" ? SneakContentType.backlight : decodedData.type == "mic" ? SneakContentType.mic : SneakContentType.brightness

            let value = CGFloat((NumberFormatter().number(from: decodedData.value) ?? 0.0).floatValue)
            let icon = decodedData.icon
            
            print(decodedData)
            
            toggleSneakPeak(status: decodedData.show, type: contentType, value: value, icon: icon)
            
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
    
    func toggleSneakPeak(status: Bool, type: SneakContentType, value: CGFloat = 0, icon: String = "") {
        if type != .music {
            close()
            if !hudReplacement {
                return
            }
        }
        DispatchQueue.main.async {
            withAnimation(.smooth) {
                self.sneakPeak.show = status
                self.sneakPeak.type = type
                self.sneakPeak.value = value
                self.sneakPeak.icon = icon
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
        if !TrayDrop.shared.isEmpty && openShelfByDefault {
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
