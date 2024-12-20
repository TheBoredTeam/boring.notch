//
//  generic.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Foundation
import Defaults

protocol LocalizedEnum: RawRepresentable, CaseIterable where RawValue == String {
    var localizedName: String { get }
}

extension LocalizedEnum {
    var localizedName: String {
        NSLocalizedString(self.rawValue, comment: "")
    }
}

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
    case home
    case shelf
}

enum SettingsEnum {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
    case extensions
}

enum DownloadIndicatorStyle: String, LocalizedEnum, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
}

enum DownloadIconStyle: String, LocalizedEnum, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum MirrorShapeEnum: String, LocalizedEnum, Defaults.Serializable {
    case rectangle = "settings.mirror.shape.rectangle"
    case circle = "settings.mirror.shape.circle"
}

enum WindowHeightMode: String, LocalizedEnum, Defaults.Serializable {
    case matchMenuBar = "settings.general.notch_match_menubar_height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "settings.general.notch_custom_height"
}

enum SliderColorEnum: String, CaseIterable, LocalizedEnum, Defaults.Serializable {
    case white = "slidercolor.white"
    case albumArt = "slidercolor.match_album_art"
    case accent = "slidercolor.match_accent"
}
