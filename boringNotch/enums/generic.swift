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
