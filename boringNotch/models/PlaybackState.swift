//
//  PlaybackState.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

enum RepeatMode: Int, Codable {
    case off = 1
    case one = 2
    case all = 3
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
    var isShuffled: Bool = false
    var repeatMode: RepeatMode = .off
    var lastUpdated: Date = Date.distantPast
    var artwork: Data?
    var volume: Double = 0.5
    var isFavorite: Bool = false

    var artworkSignature: UInt64? {
        artwork?.boringNotchSampledSignature
    }
}

extension PlaybackState: Equatable {
    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        return lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.isPlaying == rhs.isPlaying
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.currentTime == rhs.currentTime
            && lhs.duration == rhs.duration
            && lhs.isShuffled == rhs.isShuffled
            && lhs.repeatMode == rhs.repeatMode
            && lhs.artworkSignature == rhs.artworkSignature
            && lhs.isFavorite == rhs.isFavorite
    }
}

extension Data {
    /// A constant-cost identity for large artwork blobs. It deliberately samples
    /// the payload because this is used for UI change detection, not integrity.
    var boringNotchSampledSignature: UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        hash ^= UInt64(count)
        hash = hash &* 1_099_511_628_211

        guard !isEmpty else { return hash }
        let sampleCount = Swift.min(count, 32)
        for sample in 0..<sampleCount {
            let offset = sampleCount == 1 ? 0 : sample * (count - 1) / (sampleCount - 1)
            hash ^= UInt64(self[index(startIndex, offsetBy: offset)])
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}
