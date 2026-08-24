//
//  generic.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Foundation
import Defaults

public enum Style {
    case notch
    case floating
}

public enum NotchState {
    case closed
    case open
}

public enum NotchViews {
    case home
    case shelf
    case screenTime
}

enum DownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
}

enum DownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum MirrorShapeEnum: String, Defaults.Serializable {
    case rectangle = "Rectangular"
    case circle = "Circular"
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white
    case albumArt
    case accent
    
    var localizedString: String {
        switch self {
        case .white:
            return NSLocalizedString("slider_color_white", comment: "Slider color option: white")
        case .albumArt:
            return NSLocalizedString("slider_color_album_art", comment: "Slider color option: match album art")
        case .accent:
            return NSLocalizedString("slider_color_accent", comment: "Slider color option: accent color")
        }
    }
}

enum WeekStartDay: String, CaseIterable, Identifiable, Defaults.Serializable {
    case system
    case sunday
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: String { rawValue }

    /// Calendar.firstWeekday convention: 1 = Sunday … 7 = Saturday
    var firstWeekday: Int {
        switch self {
        case .system: return Calendar.current.firstWeekday
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }

    /// Display name. Specific weekdays use the system's localized weekday names
    /// (Apple-provided via Calendar — no custom strings). The system option shows
    /// the resolved first weekday in parentheses, mirroring the macOS Calendar app.
    var localizedString: String {
        let symbols = Calendar.current.weekdaySymbols  // localized full names; index 0 = Sunday
        guard !symbols.isEmpty else { return rawValue }
        if self == .system {
            let systemName = symbols[(Calendar.current.firstWeekday - 1) % symbols.count]
            let label = NSLocalizedString("System Setting", comment: "Week starts on: follow the macOS system setting")
            return "\(label) (\(systemName))"
        }
        return symbols[(firstWeekday - 1) % symbols.count]
    }
}
