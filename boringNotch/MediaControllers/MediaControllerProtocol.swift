//
//  MediaControllerProtocol.swift
//  boringNotch
//
//  Created by Alexander Greco on 2025-03-29.
//

import Foundation
import AppKit

protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: Published<PlaybackState>.Publisher { get }
    func play()
    func pause()
    func seek(to time: Double)
    func nextTrack()
    func previousTrack()
    func togglePlay()
    func isActive() -> Bool
    func updatePlaybackInfo()
}
