//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import SwiftUI

class BoringViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: BoringAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []
    
    @Published var hideOnClosed: Bool = true

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()

    /// Height of the open panel's content. Mirrors `openNotchSize.height` (190) in
    /// every tab except the Pi tab, where it follows the measured content height —
    /// clamped to [base, `expandedPanelHeight`] — so the panel grows with the answer.
    /// SwiftUI frames bind to this instead of the literal.
    @Published var openPanelHeight: CGFloat = openNotchSize.height

    /// The panel's *laid-out* height, reported each layout pass by ContentView's
    /// geometry probe. Differs from `openPanelHeight` (the target) while the panel
    /// frame is mid-animation. PiAgentView's content measurement reads this so its
    /// math only mixes values from the same layout pass — mixing the target with
    /// laid-out values produced garbage measurements during the open spring.
    /// Deliberately not @Published: it changes every animation frame and nothing
    /// should re-render off it.
    var laidOutPanelHeight: CGFloat = 0
    
    let webcamManager = WebcamManager.shared
    @Published var isCameraExpanded: Bool = false
    @Published var isRequestingAuthorization: Bool = false
    
    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation

        super.init()
        
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        Publishers.CombineLatest3($dropZoneTargeting, $dragDetectorTargeting, $generalDropTargeting)
            .map { shelf, drag, general in
                shelf || drag || general
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)

        setupDetectorObserver()
        setupPanelHeightObserver()
    }

    /// Recompute `openPanelHeight` whenever the active tab or the Pi tab's measured
    /// content height changes, so the open panel grows/shrinks with Pi's content.
    private func setupPanelHeightObserver() {
        let viewPublisher = coordinator.$currentView.removeDuplicates()
        let measuredPublisher = PiAgentManager.shared.$measuredContentHeight.removeDuplicates()

        Publishers.CombineLatest(viewPublisher, measuredPublisher)
            .receive(on: RunLoop.main)
            .sink { [weak self] view, measured in
                self?.applyPanelHeight(view: view, measuredContentHeight: measured)
            }
            .store(in: &cancellables)
    }

    /// The Pi panel's height follows its content (clamped to [base, expanded]); every
    /// other tab uses the base height. Quantized to whole points to avoid spring churn
    /// on per-token deltas.
    ///
    /// Animation gating (motion spec): streaming growth rides the height spring so many
    /// small deltas read as one continuous swell; typing growth and tab switches assign
    /// directly (the frequency rule — things the user triggers constantly don't animate).
    private func applyPanelHeight(view: NotchViews, measuredContentHeight: CGFloat) {
        let target: CGFloat = view == .pi
            ? min(max(measuredContentHeight.rounded(), openNotchSize.height), expandedPanelHeight)
            : openNotchSize.height
        guard openPanelHeight != target else { return }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if view == .pi && PiAgentManager.shared.isRunning && !reduceMotion {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85, blendDuration: 0)) {
                openPanelHeight = target
            }
        } else {
            openPanelHeight = target
        }
    }
    
    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func toggleCameraPreview() {
        if isRequestingAuthorization {
            return
        }

        switch webcamManager.authorizationStatus {
        case .authorized:
            if webcamManager.isSessionRunning {
                webcamManager.stopSession()
                isCameraExpanded = false
            } else if webcamManager.cameraAvailable {
                webcamManager.startSession()
                isCameraExpanded = true
            }

        case .denied, .restricted:
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let alert = NSAlert()
                alert.messageText = "Camera Access Required"
                alert.informativeText = "Please allow camera access in System Settings."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }

                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }

        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isRequestingAuthorization = false
            }

        default:
            break
        }
    }
    
    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {
            // When open, the visible panel can be taller than `notchSize.height`
            // (the Pi tab grows up to `expandedPanelHeight`). The hit-test must
            // cover the full open panel — using only `notchSize.height` makes a
            // cursor genuinely inside a tall panel read as "outside", which lets a
            // resize-induced phantom exit close it.
            let hoverHeight = notchState == .open ? max(openPanelHeight, notchSize.height) : notchSize.height
            let baseY = frame.maxY - hoverHeight
            let baseX = frame.midX - notchSize.width / 2

            return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
        }
        
        return false
    }

    func open() {
        self.notchSize = openNotchSize
        self.notchState = .open
        
        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
    }

    func close() {
        // Do not close while a share picker or sharing service is active
        if SharingStateManager.shared.preventNotchClose {
            return
        }
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.coordinator.sneakPeek.show = false
        self.edgeAutoOpenActive = false

        // Remember the tab the user was on. When "open last tab by default" is on
        // (now the default), nothing resets the tab — reopening lands on the same tab.
        // Only when the user opts out do we fall back to the legacy auto-switch:
        // shelf-if-it-has-files (and openShelfByDefault), otherwise home.
        if !coordinator.openLastTabByDefault {
            if !ShelfStateViewModel.shared.isEmpty && Defaults[.openShelfByDefault] {
                coordinator.currentView = .shelf
            } else {
                coordinator.currentView = .home
            }
        }
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animationLibrary.animation) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
