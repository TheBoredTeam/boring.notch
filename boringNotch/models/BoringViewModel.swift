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
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    
    let animationLibrary: BoringAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed
    
    private var expandingViewDispatch: DispatchWorkItem?
    
    @Published var dragDetectorTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []
    
    var screen: String?
    
    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()

    var notifier: TheBoringWorkerNotifier = .init()

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
    
    @AppStorage("preferred_screen_name") var preferredScreen = NSScreen.main?.localizedName ?? "Unknown" {
        didSet {
            selectedScreen = preferredScreen
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }
    
    @Published var selectedScreen: String = NSScreen.main?.localizedName ?? "Unknown"

    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true
    var notifier: TheBoringWorkerNotifier = .init()

    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screen: String? = nil) {
        animation = animationLibrary.animation

        super.init()
        
        notifier = coordinator.notifier
        self.screen = screen
        self.notchSize = getClosedNotchSize(screen: screen)
        self.closedNotchSize = notchSize

        Publishers.CombineLatest($dropZoneTargeting, $dragDetectorTargeting)
            .map { value1, value2 in
                value1 || value2
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)
        self.selectedScreen = preferredScreen
    }

    func open() {
        withAnimation(.bouncy) {
            self.notchSize = CGSize(width: openNotchSize.width, height: openNotchSize.height)
            self.notchState = .open
        }
    }

    func toggleMusicLiveActivity(status: Bool) {
        withAnimation(.smooth) {
            // self.showMusicLiveActivityOnClosed = status
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

    func close() {
        withAnimation(.smooth) {
            self.notchSize = getClosedNotchSize(screen: screen)
            closedNotchSize = notchSize
            self.notchState = .closed
        }

        // Set the current view to shelf if it contains files and the user enables openShelfByDefault
        // Otherwise, if the user has not enabled openLastShelfByDefault, set the view to home
        if !TrayDrop.shared.isEmpty && Defaults[.openShelfByDefault] {
            coordinator.currentView = .shelf
        } else if !coordinator.openLastTabByDefault {
            coordinator.currentView = .home
        }
    }
    
    func openClipboard() {
        notifier.postNotification(name: notifier.showClipboardNotification.name, userInfo: nil)
    }

    func toggleClipboard() {
        openClipboard()
    }

    func closeHello() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            self?.coordinator.firstLaunch = false
            withAnimation(self?.animationLibrary.animation) {
                self?.close()
            }
        }
    }
}
