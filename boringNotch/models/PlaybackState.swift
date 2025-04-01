//
//  PlaybackState.swift
//  boringNotch
//
//  Created by Alexander Greco on 2025-03-29.
//

import Foundation

struct PlaybackState {
    var bundleIdentifier: String
    var isPlaying: Bool = false
    var title: String = "I'm Handsome"
    var artist: String = "Me"
    var album: String = "Self Love"
    var currentTime: Double = 0
    var duration: Double = 0
    var playbackRate: Double = 1
    var isShuffled: Bool? = nil
    var isRepeating: Bool? = nil
    var lastUpdated: Date = Date.distantPast
    var artwork: Data?
}
