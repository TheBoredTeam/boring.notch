//
//  MediaControllerProtocol.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import AppKit
import Combine

protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    var channelPolicy: MediaChannelPolicy { get }
    
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
    func forceRefresh() async
}

extension MediaControllerProtocol {
    /// Force an immediate state refresh. Defaults to `updatePlaybackInfo()`; a controller whose
    /// `updatePlaybackInfo` doesn't refresh every field (e.g. YouTube Music's shuffle/repeat)
    /// overrides this to poll fully.
    func forceRefresh() async { await updatePlaybackInfo() }
}
