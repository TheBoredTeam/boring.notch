//
//  PlaybackState.swift
//  boringNotch
//
//  Created by Alexander Greco on 2025-03-29.
//

import Foundation

struct PlaybackState {
    var bundleIdentifier: String
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    var currentTime: Double
    var duration: Double
    var playbackRate: Double
    var isShuffled: Bool? = nil
    var isRepeating: Bool? = nil
    var lastUpdated: Date
    var artwork: Data?
}
