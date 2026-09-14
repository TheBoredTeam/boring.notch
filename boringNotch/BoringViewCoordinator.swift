//
//  BoringViewCoordinator.swift
//  boringNotch
//
//  Created by Alexander on 2024-11-20.
//

import AppKit
import Combine
import Defaults
import SwiftUI

enum SneakContentType {
    case lowBattery
    case bluetooth
    case wifi
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
    case privacy
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
    var accent: Color? = nil
    var targetScreenUUID: String? = nil

    /// Bumped on every show event. Views need it because the value alone cannot tell them
    /// a key was pressed: holding volume-up at 100% produces events that leave `value`
    /// untouched, and that is exactly when the "already at the limit" feedback belongs.
    var eventCount: Int = 0
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

    /// Opt out of the auto-dismiss timer, for activities that last as long as the thing
    /// they describe rather than for a fixed few seconds — a download in progress, say.
    /// A sticky item can still be preempted by a higher-priority one; it is up to whoever
    /// set it to put it back afterwards.
    var isSticky: Bool = false
}

@MainActor
class BoringViewCoordinator: ObservableObject {
    static let shared = BoringViewCoordinator()

    @Published var currentView: NotchViews = .home
    @Published var helloAnimationRunning: Bool = false
    private var sneakPeekDispatch: DispatchWorkItem?
    private var expandingViewDispatch: DispatchWorkItem?
    private var osdEnableTask: Task<Void, Never>?

    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true

    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if ShelfStateViewModel.shared.isEmpty || !Defaults[.openShelfByDefault] {
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
    
    // Legacy storage for migration
    @AppStorage("preferred_screen_name") private var legacyPreferredScreenName: String?
    
    // New UUID-based storage
    @AppStorage("preferred_screen_uuid") var preferredScreenUUID: String? {
        didSet {
            if let uuid = preferredScreenUUID {
                selectedScreenUUID = uuid
            }
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreenUUID: String = NSScreen.main?.displayUUID ?? ""

    @Published var optionKeyPressed: Bool = true
    private var accessibilityObserver: Any?
    private var osdReplacementCancellable: AnyCancellable?
    private var boringShelfCancellable: AnyCancellable?
    private var systemSectionCancellable: AnyCancellable?
    private var osdSourceCancellables: [AnyCancellable] = []

    private init() {
        // Perform migration from name-based to UUID-based storage
        if preferredScreenUUID == nil, let legacyName = legacyPreferredScreenName {
            // Try to find screen by name and migrate to UUID
            if let screen = NSScreen.screens.first(where: { $0.localizedName == legacyName }),
               let uuid = screen.displayUUID {
                preferredScreenUUID = uuid
                NSLog("✅ Migrated display preference from name '\(legacyName)' to UUID '\(uuid)'")
            } else {
                // Fallback to main screen if legacy screen not found
                preferredScreenUUID = NSScreen.main?.displayUUID
                NSLog("⚠️ Could not find display named '\(legacyName)', falling back to main screen")
            }
            // Clear legacy value after migration
            legacyPreferredScreenName = nil
        } else if preferredScreenUUID == nil {
            // No legacy value, use main screen
            preferredScreenUUID = NSScreen.main?.displayUUID
        }
        
        selectedScreenUUID = preferredScreenUUID ?? NSScreen.main?.displayUUID ?? ""
        // Observe changes to accessibility authorization and react accordingly
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if Defaults[.osdReplacement] {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }

        XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()

        // Observe changes to osdReplacement
        osdReplacementCancellable = Defaults.publisher(.osdReplacement)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self = self else { return }

                    self.osdEnableTask?.cancel()
                    self.osdEnableTask = nil

                    if change.newValue {
                        self.osdEnableTask = Task { @MainActor in
                            await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                        }
                    } else {
                        MediaKeyInterceptor.shared.stop()
                    }
                    
                    self.applyOSDSources()
                }
            }
        // Observe changes to any of the OSD source selections
        osdSourceCancellables = [
            Defaults.publisher(.osdBrightnessSource).sink { [weak self] _ in Task { @MainActor in self?.applyOSDSources() } },
            Defaults.publisher(.osdVolumeSource).sink { [weak self] _ in Task { @MainActor in self?.applyOSDSources() } }
        ]
        boringShelfCancellable = Defaults.publisher(.boringShelf)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self = self else { return }
                    if !change.newValue && self.currentView == .shelf {
                        self.currentView = .home
                    }
                }
            }

        // Same rule for the System tab: switching its content off underneath someone who is
        // looking at it has to move them somewhere that still exists.
        systemSectionCancellable = Defaults.publisher(.showNetworkInformation)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self = self else { return }
                    if !change.newValue && self.currentView == .system {
                        self.currentView = .home
                    }
                }
            }

        Task { @MainActor in
            helloAnimationRunning = firstLaunch

            if Defaults[.osdReplacement] {
                await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
            }
            self.applyOSDSources()
        }
    }
    
    @objc func sneakPeekEvent(_ notification: Notification) {
        let decoder = JSONDecoder()
        if let decodedData = try? decoder.decode(
            SharedSneakPeek.self, from: notification.userInfo?.first?.value as! Data)
        {
            let contentType =
                decodedData.type == "brightness"
                ? SneakContentType.brightness
                : decodedData.type == "volume"
                    ? SneakContentType.volume
                    : decodedData.type == "backlight"
                        ? SneakContentType.backlight
                        : decodedData.type == "mic"
                            ? SneakContentType.mic : SneakContentType.brightness

            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            let value = CGFloat((formatter.number(from: decodedData.value) ?? 0.0).floatValue)
            let icon = decodedData.icon

            print("Decoded: \(decodedData), Parsed value: \(value)")

            toggleSneakPeek(status: decodedData.show, type: contentType, value: value, icon: icon)

        } else {
            print("Failed to decode JSON data")
        }
    }

    // MARK: - Per-Screen Sneak Peek Management

    // Dictionary to hold sneak peek state for each screen UUID
    @Published var sneakPeekStates: [String: sneakPeek] = [:]
    
    // Dictionary to hold hide tasks for each screen UUID
    private var sneakPeekTasks: [String: Task<Void, Never>] = [:]
    
    // Default duration
    private var defaultSneakPeekDuration: TimeInterval = 1.5

    /// Whether the user has this particular OSD switched on. The global OSD replacement
    /// switch still gates everything; these are per-kind opt-outs beneath it.
    private func isOSDEnabled(for type: SneakContentType) -> Bool {
        guard Defaults[.osdReplacement] else { return false }
        switch type {
        case .volume: return Defaults[.osdVolumeEnabled]
        case .brightness: return Defaults[.osdBrightnessEnabled]
        case .backlight: return Defaults[.osdKeyboardBrightnessEnabled]
        default: return true
        }
    }

    /// How long an OSD stays up when the caller does not specify. Keeping this in one
    /// place means a burst of volume presses all agree on the dismissal deadline.
    private func defaultDuration(for type: SneakContentType) -> TimeInterval {
        switch type {
        case .volume: return Defaults[.osdSoundDuration]
        case .brightness, .backlight: return Defaults[.osdDisplayDuration]
        default: return 1.5
        }
    }

    func toggleSneakPeek(
        status: Bool, type: SneakContentType, duration: TimeInterval? = nil, value: CGFloat = 0,
        icon: String = "", accent: Color? = nil, targetScreenUUID: String? = nil
    ) {
        if type != .music {
            // close()
            // Dismissing must always get through, otherwise switching an OSD off while it
            // is on screen would strand it there until something else replaced it.
            if status, !isOSDEnabled(for: type) {
                return
            }
        }

        let duration = duration ?? defaultDuration(for: type)

        Task { @MainActor in
            // Helper to update state for a specific UUID
            @MainActor
            func updateState(for uuid: String) {
                // If we don't have a state for this screen yet, initialize it
                var state = self.sneakPeekStates[uuid] ?? sneakPeek(targetScreenUUID: uuid)
                
                withAnimation(.smooth) {
                    state.show = status
                    state.type = type
                    state.value = value
                    state.icon = icon
                    state.accent = accent
                    state.targetScreenUUID = uuid // Ensure UUID is set
                    // Only show events count: a hide must not read as another key press.
                    if status { state.eventCount &+= 1 }
                    self.sneakPeekStates[uuid] = state
                }
                
                if status {
                    self.scheduleSneakPeekHide(for: uuid, duration: duration)
                } else {
                    self.sneakPeekTasks[uuid]?.cancel()
                    self.sneakPeekTasks[uuid] = nil
                }
            }
            
            if let targetUUID = targetScreenUUID {
                // Update specific screen
                updateState(for: targetUUID)
            } else {
                // Update ALL connected screens + the main screen as fallback
                // We use known screen UUIDs from NSScreen
                let screens = NSScreen.screens.compactMap { $0.displayUUID }
                if screens.isEmpty {
                    // Fallback if no screens detected (unlikely in UI app but safe)
                     if let mainUUID = NSScreen.main?.displayUUID {
                         updateState(for: mainUUID)
                     }
                } else {
                    for uuid in screens {
                        updateState(for: uuid)
                    }
                }
            }
        }

        if type == .mic {
            currentMicStatus = value == 1
        }
    }

     func applyOSDSources() {
        if NotchSpaceManager.shared.notchSpace.windows.isEmpty {
            BetterDisplayManager.shared.stopObserving()
            LunarManager.shared.stopListening()
            LunarManager.shared.configureLunarOSD(hide: false)
            MediaKeyInterceptor.shared.stop()
            return
        }

        guard Defaults[.osdReplacement] else {
            BetterDisplayManager.shared.stopObserving()
            LunarManager.shared.stopListening()
            LunarManager.shared.configureLunarOSD(hide: false)
            MediaKeyInterceptor.shared.stop()
            return
        }

        let brightness = Defaults[.osdBrightnessSource]
        let volume = Defaults[.osdVolumeSource]

        Task { @MainActor in
            await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
        }
        // BetterDisplay is used when either brightness or volume is set to it
        if brightness == .betterDisplay || volume == .betterDisplay {
            BetterDisplayManager.shared.startObserving()
        } else {
            BetterDisplayManager.shared.stopObserving()
        }

        // Lunar only supports brightness; disable Lunar's OSD when we replace it, restore when we don't
        if brightness == .lunar {
            LunarManager.shared.configureLunarOSD(hide: true)
            LunarManager.shared.startListening()
        } else {
            LunarManager.shared.stopListening()
            LunarManager.shared.configureLunarOSD(hide: false)
        }
    }

    func shouldShowSneakPeek(on screenUUID: String?) -> Bool {
        guard let uuid = screenUUID else { return false }
        return sneakPeekStates[uuid]?.show == true
    }
    
    var isAnySneakPeekShowing: Bool {
        return sneakPeekStates.values.contains { $0.show }
    }
    
    // Helper to get state safely for binding/reading
    func sneakPeekState(for screenUUID: String?) -> sneakPeek {
        guard let uuid = screenUUID else { return sneakPeek() }
        return sneakPeekStates[uuid] ?? sneakPeek(targetScreenUUID: uuid)
    }
    
    // Helper to get binding for SwiftUI views
    func binding(for screenUUID: String?) -> Binding<sneakPeek> {
        Binding(
            get: { [weak self] in
                guard let self = self, let uuid = screenUUID else { return sneakPeek() }
                return self.sneakPeekStates[uuid] ?? sneakPeek(targetScreenUUID: uuid)
            },
            set: { [weak self] newValue in
                guard let self = self, let uuid = screenUUID else { return }
                self.sneakPeekStates[uuid] = newValue
            }
        )
    }

    private func scheduleSneakPeekHide(for screenUUID: String, duration: TimeInterval) {
        sneakPeekTasks[screenUUID]?.cancel()

        sneakPeekTasks[screenUUID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            
            await MainActor.run {
                withAnimation {
                    // We only want to hide it, not reset everything instantly which might cause glitches
                    if var state = self.sneakPeekStates[screenUUID] {
                         state.show = false
                         // Optional: reset type to something default if needed, but keeping last state is often fine until next show
                         // keeping original logic:
                         state.type = .music 
                         self.sneakPeekStates[screenUUID] = state
                    }
                }
            }
        }
    }

    /// Relative importance of the transient item occupying the expanding view slot.
    ///
    /// There is only one slot, so a lower-priority item must not interrupt a
    /// higher-priority one that is already on screen. No save/restore is needed: the
    /// notch's persistent content (Now Playing, the idle face) is derived live from
    /// `MusicManager` rather than stored, so it reappears on its own once the transient
    /// item expires.
    private func priority(of type: SneakContentType) -> Int {
        switch type {
        case .lowBattery: return 30
        // Knowing the microphone just went live matters, and the activity is a brief
        // transition blip rather than something that occupies the notch for a whole call.
        case .privacy: return 25
        case .battery: return 20
        // Wi-Fi ties with Bluetooth deliberately: they are peers, and the preemption guard
        // is a strict `<`, so the newer of two connectivity events wins — which is the one
        // worth seeing.
        case .bluetooth, .wifi: return 15
        case .download: return 10
        case .brightness, .volume, .backlight, .mic, .music: return 0
        }
    }

    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium,
        sticky: Bool = false
    ) {
        Task { @MainActor in
            // Dismissing is always allowed; showing must not preempt something more
            // important that is already visible.
            if status, self.expandingView.show, self.expandingView.type != type,
               self.priority(of: type) < self.priority(of: self.expandingView.type)
            {
                return
            }

            withAnimation(.smooth) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
                self.expandingView.browser = browser
                self.expandingView.isSticky = status && sticky
            }
        }
    }

    private var expandingViewTask: Task<Void, Never>?

    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            // A sticky item stays until its owner takes it down, so it gets no timer.
            if expandingView.show, !expandingView.isSticky {
                expandingViewTask?.cancel()
                let duration: TimeInterval
                switch expandingView.type {
                case .download: duration = 2
                // A low-battery warning is worth reading, so it lingers a little longer.
                case .lowBattery: duration = 5
                default: duration = 3
                }
                let currentType = expandingView.type
                expandingViewTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(duration))
                    guard let self = self, !Task.isCancelled else { return }
                    self.toggleExpandingView(status: false, type: currentType)
                }
            } else {
                expandingViewTask?.cancel()
            }
        }
    }
    
    /// Take every screen's sneak peek down at once, e.g. when the screen locks.
    func hideAllSneakPeeks() {
        for uuid in sneakPeekStates.keys {
            sneakPeekTasks[uuid]?.cancel()
            sneakPeekTasks[uuid] = nil
            sneakPeekStates[uuid]?.show = false
        }
    }

    func showEmpty() {
        currentView = .home
    }
}
