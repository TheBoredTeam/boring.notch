//
//  PlaybackState.swift
//  boringNotch
//
//  Created by Alexander Greco on 2025-03-29.
//

import Foundation

enum RepeatMode: Int, Codable {
    case off = 0
    case all = 1
    case one = 2
}

struct PlaybackState {
    var bundleIdentifier: String
    var isPlaying: Bool = false
    var title: String = "I'm Handsome"
    var artist: String = "Me"
    var album: String = "Self Love"
    var currentTime: Double = 0
    var duration: Double = 0
    var playbackRate: Double = 1
    var isShuffled: Bool? = false
    var repeatMode: RepeatMode = .off
    var lastUpdated: Date = Date.distantPast
    var artwork: Data?
}
