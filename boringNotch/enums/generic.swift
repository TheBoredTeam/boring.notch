//
//  generic.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Foundation

public enum Style {
    case notch
    case floating
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

public enum NotchViews {
    case empty
    case music
    case menu
    case weather
}

enum SettingsEnum {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
}

enum DownloadIndicatorStyle {
    case progress
    case percentage
}

enum DownloadIconStyle {
    case onlyAppIcon
    case onlyIcon
    case iconAndAppIcon
}
