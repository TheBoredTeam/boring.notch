//
//  YandexMusicController.swift
//  boringNotch
//
//  Created by Anatoly on 2026-04-27.
//

import AppKit
import Combine
import Foundation

class YandexMusicController: MediaControllerProtocol {
    private enum Constants {
        static let bundleIdentifier = "ru.yandex.desktop.music"
    }

    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: Constants.bundleIdentifier
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool { false }
    var supportsFavorite: Bool { false }

    private var cancellables = Set<AnyCancellable>()
    private let nowPlayingController: NowPlayingController?

    init() {
        self.nowPlayingController = NowPlayingController()
        bindNowPlaying()
    }

    private func bindNowPlaying() {
        nowPlayingController?.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                guard state.bundleIdentifier == Constants.bundleIdentifier else { return }
                self.playbackState = state
            }
            .store(in: &cancellables)
    }

    func setFavorite(_ favorite: Bool) async {}

    func play() async {
        await nowPlayingController?.play()
    }

    func pause() async {
        await nowPlayingController?.pause()
    }

    func seek(to time: Double) async {
        await nowPlayingController?.seek(to: time)
    }

    func nextTrack() async {
        await nowPlayingController?.nextTrack()
    }

    func previousTrack() async {
        await nowPlayingController?.previousTrack()
    }

    func togglePlay() async {
        await nowPlayingController?.togglePlay()
    }

    func toggleShuffle() async {}
    func toggleRepeat() async {}
    func setVolume(_ level: Double) async {}

    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Constants.bundleIdentifier
        }
    }

    func updatePlaybackInfo() async {
        await nowPlayingController?.updatePlaybackInfo()
    }
}
