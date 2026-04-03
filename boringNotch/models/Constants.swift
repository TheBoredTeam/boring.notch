//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import SwiftUI
import Defaults

// MARK: - File System Paths
private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

enum MusicPlayerVisibilityMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case always = "Always"
    case onlyWhenPlaying = "Only when music is playing"
    case never = "Never"

    var id: String { self.rawValue }
}

// Define notification names at file scope
extension Notification.Name {
    // MARK: - Media
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
    
    // MARK: - Display
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    
    // MARK: - Shelf
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
    
    // MARK: - System
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
    
    // MARK: - Sharing
    static let sharingDidFinish = Notification.Name("com.boringNotch.sharingDidFinish")
    
    // MARK: - UI
    static let accentColorChanged = Notification.Name("AccentColorChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying
    case appleMusic
    case spotify
    case youtubeMusic
    
    var id: String { self.rawValue }

    var localizedString: String {
        switch self {
        case .nowPlaying:
            return NSLocalizedString("Now Playing", comment: "")
        case .appleMusic:
            return "Apple Music"
        case .spotify:
            return "Spotify"
        case .youtubeMusic:
            return "YouTube Music"
        }
    }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard
    case inline
    
    var id: String { self.rawValue }
    
    var localizedString: String {
        switch self {
        case .standard:
            return NSLocalizedString("sneak_peek_standard", comment: "Sneak Peek style: Default")
        case .inline:
            return NSLocalizedString("sneak_peek_inline", comment: "Sneak Peek style: Inline")
        }
    }
}

// Action to perform when Option (⌥) is held while pressing media keys
enum OptionKeyAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case openSettings
    case showOSD
    case none

    var id: String { self.rawValue }
    
    var localizedString: String {
        switch self {
        case .openSettings:
            return NSLocalizedString("option_key_open_system_settings", comment: "Option (⌥) key behavior: Open System Settings")
        case .showOSD:
            return NSLocalizedString("option_key_show_osd", comment: "Option (⌥) key behavior: Show OSD")
        case .none:
            return NSLocalizedString("option_key_no_action", comment: "Option (⌥) key behavior: No action")
        }
    }
}

enum WeatherTemperatureUnit: String, CaseIterable, Identifiable, Defaults.Serializable {
    case celsius
    case fahrenheit

    var id: String { self.rawValue }

    var symbol: String {
        switch self {
        case .celsius:
            return "C"
        case .fahrenheit:
            return "F"
        }
    }

    var displayName: String {
        switch self {
        case .celsius:
            return "Celsius"
        case .fahrenheit:
            return "Fahrenheit"
        }
    }
}

enum WeatherContentPreference: String, CaseIterable, Identifiable, Defaults.Serializable {
    case currentOnly
    case currentAndForecast

    var id: String { self.rawValue }
}

// Source/provider for OSD control (user-facing: "Source")
enum OSDControlSource: String, CaseIterable, Identifiable, Defaults.Serializable {
    case builtin
    case betterDisplay = "BetterDisplay"
    case lunar = "Lunar"

    var id: String { self.rawValue }
    
    var localizedString: String {
        switch self {
        case .builtin:
            return NSLocalizedString("osd_sources_built_in", comment: "OSD Sources: Built-in")
        case .betterDisplay:
            return "BetterDisplay"
        case .lunar:
            return "Lunar"
        }
    }
}

enum UpdateChannel: String, CaseIterable, Identifiable, Defaults.Serializable {
    case stable
    case beta
    case dev

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable:
            return NSLocalizedString("Stable", comment: "Update channel: stable")
        case .beta:
            return NSLocalizedString("Beta", comment: "Update channel: beta")
        case .dev:
            return NSLocalizedString("Dev (Nightly)", comment: "Update channel: dev nightly")
        }
    }

    var feedURLString: String {
        switch self {
        case .stable:
            return "https://TheBoredTeam.github.io/boring.notch/appcast.xml"
        case .beta:
            return "https://TheBoredTeam.github.io/boring.notch/appcast.xml"
        case .dev:
            return "https://raw.githubusercontent.com/TheBoredTeam/boring.notch/dev/updater/appcast-dev.xml"
        }
    }

    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable:
            return []
        case .beta:
            return ["beta"]
        case .dev:
            return ["dev"]
        }
    }
}

extension Defaults.Keys {
    // MARK: General
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "Flying Rabbit 🐇🪽")
    static let updateChannel = Key<UpdateChannel>("updateChannel", default: .stable)
    
    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableOpeningAnimation = Key<Bool>("enableOpeningAnimation", default: true)
    static let animationSpeedMultiplier = Key<Double>("animationSpeedMultiplier", default: 1.0)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)
    
    // MARK: Appearance
    //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: false)
    static let isMirrored = Key<Bool>("isMirrored", default: true)
    static let mirrorShape = Key<MirrorShapeEnum>("mirrorShape", default: MirrorShapeEnum.rectangle)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)

    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: false)
    static let showWeather = Key<Bool>("showWeather", default: false)
    static let weatherCity = Key<String>("weatherCity", default: "Cupertino")
    static let weatherUnit = Key<WeatherTemperatureUnit>("weatherUnit", default: .celsius)
    static let weatherRefreshMinutes = Key<Int>("weatherRefreshMinutes", default: 30)
    static let weatherContentPreference = Key<WeatherContentPreference>("weatherContentPreference", default: .currentAndForecast)
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    
    // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    
    // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: false)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: false)
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)
    static let musicPlayerVisibilityMode = Key<MusicPlayerVisibilityMode>(
        "musicPlayerVisibilityMode",
        default: .always
    )
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )
    
    // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: true)
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: true)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: true)
    
    // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)
    
    // MARK: OSD
    static let osdReplacement = Key<Bool>("osdReplacement", default: false)
    static let inlineOSD = Key<Bool>("inlineOSD", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showOpenNotchOSD = Key<Bool>("showOpenNotchOSD", default: true)
    static let showOpenNotchOSDPercentage = Key<Bool>("showOpenNotchOSDPercentage", default: true)
    static let showClosedNotchOSDPercentage = Key<Bool>("showClosedNotchOSDPercentage", default: false)
    // Option key modifier behaviour for media keys
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: OptionKeyAction.openSettings)
    // Brightness/volume/keyboard source selection
    static let osdBrightnessSource = Key<OSDControlSource>("osdBrightnessSource", default: .builtin)
    static let osdVolumeSource = Key<OSDControlSource>("osdVolumeSource", default: .builtin)
    
    // MARK: Shelf
    static let boringShelf = Key<Bool>("boringShelf", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let quickShareProvider = Key<String>("quickShareProvider", default: QuickShareProvider.defaultProvider.id)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    
    // MARK: Calendar
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let showFullEventTitles = Key<Bool>("showFullEventTitles", default: false)
    static let autoScrollToNextEvent = Key<Bool>("autoScrollToNextEvent", default: true)
    
    // MARK: Fullscreen Media Detection
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)
    
    // MARK: Advanced Settings
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData", default: nil)
    // Show or hide the title bar
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    static let hideNonNotchedFromMissionControl = Key<Bool>("hideNonNotchedFromMissionControl", default: true)
    // Normalize scroll/gesture direction so when macOS "Natural scrolling" is disabled, it doesn't invert gestures
    static let normalizeGestureDirection = Key<Bool>("normalizeGestureDirection", default: true)
    
    // Helper to determine the default media controller based on NowPlaying deprecation status
    static var defaultMediaController: MediaControllerType {
        if MusicManager.shared.isNowPlayingDeprecated {
            return .appleMusic
        } else {
            return .nowPlaying
        }
    }

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)
}
