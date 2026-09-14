//
//  MediaControllerProtocol.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import Combine

@MainActor
protocol MediaControllerProtocol: AnyObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    var supportsVolumeControl: Bool { get }
    var supportsFavorite: Bool { get }
    var capabilities: MediaCapabilities { get }
    
    func setFavorite(_ favorite: Bool) async
    func play() async
    func pause() async
    func seek(to time: Double) async
    func nextTrack() async
    func previousTrack() async
    func togglePlay() async
    func toggleShuffle() async
    func toggleRepeat() async
    func setVolume(_ level: Double) async
    func isActive() -> Bool
    func updatePlaybackInfo() async
}

@MainActor
protocol NowPlayingRuntimeControlling: MediaControllerProtocol {
    var runtimeFailures: AsyncStream<Void> { get }

    func startRuntimeStream()
    func stopRuntimeStream()
}

extension MediaControllerProtocol {
    var capabilities: MediaCapabilities {
        MediaCapabilities(favorite: supportsFavorite)
    }
}

enum MediaCommand: Equatable {
    case favorite(Bool)
    case shuffle(Bool)
    case repeatMode(RepeatMode)

    func isSupported(by capabilities: MediaCapabilities) -> Bool {
        switch self {
        case .favorite: capabilities.favorite
        case .shuffle: capabilities.shuffle
        case .repeatMode(let mode): capabilities.repeatModes.count > 1 && capabilities.repeatModes.contains(mode)
        }
    }

    func isConfirmed(by state: PlaybackState) -> Bool {
        switch self {
        case .favorite(let value): state.isFavorite == value
        case .shuffle(let value): state.isShuffled == value
        case .repeatMode(let value): state.repeatMode == value
        }
    }

    @MainActor
    @discardableResult
    func perform(on controller: any MediaControllerProtocol, capabilities: MediaCapabilities) async -> Bool {
        guard isSupported(by: capabilities) else { return false }
        switch self {
        case .favorite(let value): await controller.setFavorite(value)
        case .shuffle: await controller.toggleShuffle()
        case .repeatMode: await controller.toggleRepeat()
        }
        return true
    }
}

enum MediaCommandStatus: Equatable {
    case idle, pending, confirmed, failed
}
