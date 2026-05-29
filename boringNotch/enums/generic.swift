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
