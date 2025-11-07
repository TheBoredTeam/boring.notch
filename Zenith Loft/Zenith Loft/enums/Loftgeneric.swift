import Foundation
import Defaults

public enum LoftStyle {
    case notch
    case floating
}

public enum LoftContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum LoftNotchState {
    case closed
    case open
}

public enum LoftNotchViews {
    case home
    case shelf
}

enum LoftSettingsCategory {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
    case extensions
}

enum LoftDownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
}

enum LoftDownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum LoftMirrorShape: String, Defaults.Serializable {
    case rectangle = "Rectangular"
    case circle = "Circular"
}

enum LoftWindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum LoftSliderColor: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
}
