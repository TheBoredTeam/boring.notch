//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import SwiftUI
import Defaults

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

func defaultWeatherCityName() -> String {
    let fallback = TimeZone.current.identifier
        .split(separator: "/")
        .last
        .map(String.init)?
        .replacingOccurrences(of: "_", with: " ")

    if let fallback, !fallback.isEmpty {
        return fallback
    }

    return "San Francisco"
}

struct CustomVisualizer: Codable, Hashable, Equatable, Defaults.Serializable {
    let UUID: UUID
    var name: String
    var url: URL
    var speed: CGFloat = 1.0
}

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"
    
    var id: String { self.rawValue }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard = "Default"
    case inline = "Inline"
    
    var id: String { self.rawValue }
}

// Action to perform when Option (⌥) is held while pressing media keys
enum OptionKeyAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case openSettings = "Open System Settings"
    case showHUD = "Show HUD"
    case none = "No Action"

    var id: String { self.rawValue }
}

enum WeatherTemperatureUnit: String, CaseIterable, Identifiable, Defaults.Serializable {
    case celsius = "Celsius"
    case fahrenheit = "Fahrenheit"

    var id: String { self.rawValue }

    var apiValue: String {
        switch self {
        case .celsius:
            return "celsius"
        case .fahrenheit:
            return "fahrenheit"
        }
    }

    var symbol: String {
        switch self {
        case .celsius:
            return "°C"
        case .fahrenheit:
            return "°F"
        }
    }

    var windSpeedAPIValue: String {
        switch self {
        case .celsius:
            return "kmh"
        case .fahrenheit:
            return "mph"
        }
    }

    var windSpeedLabel: String {
        switch self {
        case .celsius:
            return "km/h"
        case .fahrenheit:
            return "mph"
        }
    }
}

enum WeatherLocationMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case automatic = "Automatic location"
    case manualCity = "Manual city"

    var id: String { self.rawValue }
}

struct QuickLaunchAppItem: Codable, Hashable, Equatable, Identifiable, Defaults.Serializable {
    var name: String
    var appPath: String
    var bundleIdentifier: String

    var id: String {
        appPath.isEmpty ? bundleIdentifier : appPath
    }

    var displayName: String {
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }

        if !appPath.isEmpty {
            return URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
        }

        return bundleIdentifier
    }

    init(name: String, appPath: String, bundleIdentifier: String = "") {
        self.name = name
        self.appPath = appPath
        self.bundleIdentifier = bundleIdentifier
    }

    init?(appURL: URL) {
        let standardizedURL = appURL.standardizedFileURL
        guard standardizedURL.pathExtension == "app" else { return nil }

        let bundle = Bundle(url: standardizedURL)
        let resolvedName =
            (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? standardizedURL.deletingPathExtension().lastPathComponent

        self.init(
            name: resolvedName,
            appPath: standardizedURL.path,
            bundleIdentifier: bundle?.bundleIdentifier ?? ""
        )
    }
}

enum PomodoroPhaseDefaults: String, Defaults.Serializable {
    case focus
    case shortBreak
    case longBreak
}

enum HomeWidgetKind: String, CaseIterable, Identifiable, Defaults.Serializable {
    case weather
    case pomodoro
    case quickLaunch
    case calendar
    case media
    case hidden

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weather:
            return "Weather"
        case .pomodoro:
            return "Pomodoro"
        case .quickLaunch:
            return "Quick launch"
        case .calendar:
            return "Calendar"
        case .media:
            return "Media controls"
        case .hidden:
            return "Hidden"
        }
    }

    var systemImage: String {
        switch self {
        case .weather:
            return "cloud.sun"
        case .pomodoro:
            return "timer"
        case .quickLaunch:
            return "square.grid.2x2"
        case .calendar:
            return "calendar"
        case .media:
            return "music.note"
        case .hidden:
            return "eye.slash"
        }
    }
}

func defaultQuickLaunchApps() -> [QuickLaunchAppItem] {
    let candidatePaths = [
        "/System/Applications/Safari.app",
        "/System/Applications/Notes.app",
        "/System/Applications/Calendar.app",
        "/System/Applications/Music.app",
    ]

    return candidatePaths.compactMap { path in
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return QuickLaunchAppItem(appURL: url)
    }
}

func defaultHomeWidgetSlots() -> [HomeWidgetKind] {
    [.weather, .pomodoro, .quickLaunch, .calendar]
}

func normalizedHomeWidgetSlots(_ slots: [HomeWidgetKind]) -> [HomeWidgetKind] {
    let maxSlots = 4
    var normalized = Array(slots.prefix(maxSlots))
    if normalized.count < maxSlots {
        normalized.append(contentsOf: Array(repeating: .hidden, count: maxSlots - normalized.count))
    }
    return normalized
}

extension Defaults.Keys {
    // MARK: General
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "Flying Rabbit 🐇🪽")
    
    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
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
    static let showEmojis = Key<Bool>("showEmojis", default: false)
    //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: false)
    static let mirrorShape = Key<MirrorShapeEnum>("mirrorShape", default: MirrorShapeEnum.rectangle)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)

    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: false)
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    static let useMusicVisualizer = Key<Bool>("useMusicVisualizer", default: true)
    static let customVisualizers = Key<[CustomVisualizer]>("customVisualizers", default: [])
    static let selectedVisualizer = Key<CustomVisualizer?>("selectedVisualizer", default: nil)
    static let aiChatEnabled = Key<Bool>("aiChatEnabled", default: true)
    static let aiServiceBaseURL = Key<String>("aiServiceBaseURL", default: "https://api.openai.com")
    static let aiServiceModel = Key<String>("aiServiceModel", default: "gpt-4o-mini")
    static let aiServiceAPIKey = Key<String>("aiServiceAPIKey", default: "")
    static let aiSystemPrompt = Key<String>(
        "aiSystemPrompt",
        default: "You are a concise assistant inside a macOS notch utility. Answer in the user's language. Use available local context when relevant, and clearly say when local context is unavailable instead of guessing."
    )
    static let aiTemperature = Key<Double>("aiTemperature", default: 0.35)
    static let aiCalendarContextEnabled = Key<Bool>("aiCalendarContextEnabled", default: true)
    static let aiCalendarWriteEnabled = Key<Bool>("aiCalendarWriteEnabled", default: true)
    static let aiChatPanelWidth = Key<CGFloat>("aiChatPanelWidth", default: aiChatPanelDefaultSize.width)
    static let aiChatPanelHeight = Key<CGFloat>("aiChatPanelHeight", default: aiChatPanelDefaultSize.height)
    static let aiKnowledgeRetrievalEnabled = Key<Bool>("aiKnowledgeRetrievalEnabled", default: true)
    static let aiKnowledgeRetrievalLimit = Key<Int>("aiKnowledgeRetrievalLimit", default: 3)
    static let weatherFeatureEnabled = Key<Bool>("weatherFeatureEnabled", default: true)
    static let weatherLocationMode = Key<WeatherLocationMode>(
        "weatherLocationMode",
        default: .automatic
    )
    static let weatherCity = Key<String>("weatherCity", default: defaultWeatherCityName())
    static let weatherTemperatureUnit = Key<WeatherTemperatureUnit>(
        "weatherTemperatureUnit",
        default: .celsius
    )
    static let pomodoroEnabled = Key<Bool>("pomodoroEnabled", default: true)
    static let pomodoroFocusMinutes = Key<Int>("pomodoroFocusMinutes", default: 25)
    static let pomodoroShortBreakMinutes = Key<Int>("pomodoroShortBreakMinutes", default: 5)
    static let pomodoroLongBreakMinutes = Key<Int>("pomodoroLongBreakMinutes", default: 15)
    static let pomodoroLongBreakInterval = Key<Int>("pomodoroLongBreakInterval", default: 4)
    static let pomodoroAutoStartNextPhase = Key<Bool>("pomodoroAutoStartNextPhase", default: false)
    static let quickLaunchEnabled = Key<Bool>("quickLaunchEnabled", default: true)
    static let quickLaunchApps = Key<[QuickLaunchAppItem]>(
        "quickLaunchApps",
        default: defaultQuickLaunchApps()
    )
    static let homeWidgetSlots = Key<[HomeWidgetKind]>(
        "homeWidgetSlots",
        default: defaultHomeWidgetSlots()
    )
    
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
    
    // MARK: HUD
    static let hudReplacement = Key<Bool>("hudReplacement", default: false)
    static let inlineHUD = Key<Bool>("inlineHUD", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showOpenNotchHUD = Key<Bool>("showOpenNotchHUD", default: true)
    static let showOpenNotchHUDPercentage = Key<Bool>("showOpenNotchHUDPercentage", default: true)
    static let showClosedNotchHUDPercentage = Key<Bool>("showClosedNotchHUDPercentage", default: false)
    // Option key modifier behaviour for media keys
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: OptionKeyAction.openSettings)
    
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
