//
//  SpotifyMusicProvider.swift
//  boringNotch
//
//  Created by Dan on 4/15/26.
//

protocol SpotifyProvider {
    var supportsFavorite: Bool { get }

    func getPlayerState() async -> SpotifyPlayerState
    func play() async
    func pause() async
    func togglePlay() async
    func nextTrack() async
    func previousTrack() async
    func seek(to time: Double) async
    func setVolume(_ volume: Int) async
    func setShuffle(_ enabled: Bool) async
    func setRepeat(_ enabled: Bool) async
    func isTrackLiked(id: String) async -> Bool
    func setLiked(_ liked: Bool, id: String) async
}
