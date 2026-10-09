//
//  MusicControlButton.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-16.
//

import Defaults
import Foundation

enum MusicControlButton: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case shuffle
    case previous
    case playPause
    case next
    case repeatMode
    case volume
    case favorite
    case goBackward
    case goForward
    case mediaOutput
    case none

    var id: String { rawValue }

    /// Shuffle and media output round out the default row. The previous
    /// default left two empty slots, so a fresh install showed only three
    /// transport buttons with dead space either side.
    static let defaultLayout: [MusicControlButton] = [
        .shuffle,
        .previous,
        .playPause,
        .next,
        .mediaOutput
    ]

    static let minSlotCount: Int = 3
    static let maxSlotCount: Int = 5

    static let pickerOptions: [MusicControlButton] = [
        .shuffle,
        .previous,
        .playPause,
        .next,
        .repeatMode,
        .favorite,
        .volume,
        .goBackward,
        .goForward,
        .mediaOutput
    ]

    var label: String {
        switch self {
        case .shuffle:
            return String(localized: "Shuffle")
        case .previous:
            return String(localized: "Previous")
        case .playPause:
            return String(localized: "Play/Pause")
        case .next:
            return String(localized: "Next")
        case .repeatMode:
            return String(localized: "Repeat")
        case .volume:
            return String(localized: "Volume")
        case .favorite:
            return String(localized: "Favorite")
        case .goBackward:
            return String(localized: "Backward 15s")
        case .goForward:
            return String(localized: "Forward 15s")
        case .mediaOutput:
            return String(localized: "Audio output")
        case .none:
            return String(localized: "Empty slot")
        }
    }

    func actionLabel(isPlaying: Bool, isFavorite: Bool) -> String {
        switch self {
        case .playPause:
            return isPlaying ? String(localized: "Pause") : String(localized: "Play")
        case .favorite:
            return isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites")
        default:
            return label
        }
    }

    var iconName: String {
        switch self {
        case .shuffle:
            return "shuffle"
        case .previous:
            return "backward.fill"
        case .playPause:
            return "playpause"
        case .next:
            return "forward.fill"
        case .repeatMode:
            return "repeat"
        case .volume:
            return "speaker.wave.2.fill"
        case .favorite:
            return "heart"
        case .goBackward:
            return "gobackward.15"
        case .goForward:
            return "goforward.15"
        case .mediaOutput:
            // Placeholder for the settings picker; the live button swaps in
            // the actual route's glyph (Mac / headphones / AirPods).
            return "macbook"
        case .none:
            return ""
        }
    }

    var prefersLargeScale: Bool {
        self == .playPause
    }
}
