//
//  MediaChannelPolicy.swift
//  boringNotch
//
//  Per-connector, per-channel gating: each media source declares, for every control channel,
//  whether it is reliably supported, present-but-unavailable, or not worth showing.
//

import Foundation

/// How a single media-control channel should be surfaced for the active source.
enum ChannelSupport {
    case supported   // works reliably -> normal, interactive
    case disabled    // exists but unreliable/unsupported -> shown greyed, non-interactive
    case hidden      // not worth showing -> removed from the toolbar
}

/// Per-channel gating policy a connector advertises. Every channel is declared explicitly so
/// each connector reads as a complete, greppable capability table.
struct MediaChannelPolicy: Equatable {
    var playPause: ChannelSupport
    var previous: ChannelSupport
    var next: ChannelSupport
    var seek: ChannelSupport
    var shuffle: ChannelSupport
    var repeatMode: ChannelSupport
    var favorite: ChannelSupport
    var volume: ChannelSupport

    static let allSupported = MediaChannelPolicy(
        playPause: .supported, previous: .supported, next: .supported, seek: .supported,
        shuffle: .supported, repeatMode: .supported, favorite: .supported, volume: .supported
    )
}
