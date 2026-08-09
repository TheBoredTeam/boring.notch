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
    case none

    var id: String { rawValue }

    static let defaultLayout: [MusicControlButton] = [
        .none,
        .previous,
        .playPause,
        .next,
        .none
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
        .goForward
    ]

    /// Localised display name for the slot palette in
    /// ``MusicSlotConfigurationView``.  Uses ``NSLocalizedString`` so the
    /// label round-trips through ``Localizable.xcstrings`` (and therefore
    /// Crowdin) instead of being emitted as raw English. (#1090)
    var localizedString: String {
        switch self {
        case .shuffle:
            return NSLocalizedString(
                "music_control_shuffle",
                comment: "Music control button label: Shuffle")
        case .previous:
            return NSLocalizedString(
                "music_control_previous",
                comment: "Music control button label: Previous track")
        case .playPause:
            return NSLocalizedString(
                "music_control_play_pause",
                comment: "Music control button label: Play/Pause")
        case .next:
            return NSLocalizedString(
                "music_control_next",
                comment: "Music control button label: Next track")
        case .repeatMode:
            return NSLocalizedString(
                "music_control_repeat",
                comment: "Music control button label: Repeat mode")
        case .volume:
            return NSLocalizedString(
                "music_control_volume",
                comment: "Music control button label: Volume")
        case .favorite:
            return NSLocalizedString(
                "music_control_favorite",
                comment: "Music control button label: Favorite (heart) current track")
        case .goBackward:
            return NSLocalizedString(
                "music_control_go_backward_15",
                comment: "Music control button label: Seek backward 15 seconds")
        case .goForward:
            return NSLocalizedString(
                "music_control_go_forward_15",
                comment: "Music control button label: Seek forward 15 seconds")
        case .none:
            return NSLocalizedString(
                "music_control_empty_slot",
                comment: "Music control button label: Empty slot placeholder")
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
        case .none:
            return ""
        }
    }

    var prefersLargeScale: Bool {
        self == .playPause
    }
}
