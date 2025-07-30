//
//  MediaControllerProtocol.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import AppKit

protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: Published<PlaybackState>.Publisher { get }
    func play() async
    func pause() async
    func seek(to time: Double) async
    func nextTrack() async
    func previousTrack() async
    func togglePlay() async
    func toggleShuffle() async
    func toggleRepeat() async
    func isActive() -> Bool
    func updatePlaybackInfo()
}
