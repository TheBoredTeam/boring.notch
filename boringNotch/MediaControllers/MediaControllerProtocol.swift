//
//  MediaControllerProtocol.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import AppKit
import Combine
import Foundation

protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    var supportsVolumeControl: Bool { get }
    var supportsFavorite: Bool { get }
    
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

protocol QueueProvidingMediaController: MediaControllerProtocol {
    var queueSupported: Bool { get }
    var queueAuthState: SpotifyQueueAuthState { get }
    var queueItems: [SpotifyQueueItem] { get }
    var isLoadingQueue: Bool { get }
    var queueErrorMessage: String? { get }
    var queueAuthStatePublisher: AnyPublisher<SpotifyQueueAuthState, Never> { get }
    var queueItemsPublisher: AnyPublisher<[SpotifyQueueItem], Never> { get }
    var isLoadingQueuePublisher: AnyPublisher<Bool, Never> { get }
    var queueErrorPublisher: AnyPublisher<String?, Never> { get }

    func connectQueue() async
    func disconnectQueue()
    func refreshQueue() async
    func playQueueItem(_ item: SpotifyQueueItem) async
}
