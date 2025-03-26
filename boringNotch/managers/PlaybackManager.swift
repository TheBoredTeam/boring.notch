    //
    //  PlaybackManager.swift
    //  boringNotch
    //
    //  Created by Harsh Vardhan  Goswami  on  04/08/24.
    //


import SwiftUI
import AppKit
import Combine

class PlaybackManager: ObservableObject {
    @Published var MrMediaRemoteSendCommandFunction:@convention(c) (Int, AnyObject?) -> Void
    @Published var MrMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    
    private var musicManager: MusicManager

    init(musicManager: MusicManager) {
        self.musicManager = musicManager
        self.MrMediaRemoteSendCommandFunction = {_,_ in }
        self.MrMediaRemoteSetElapsedTimeFunction = { _ in }
        handleLoadMediaHandlerApis()
    }
    
    private func handleLoadMediaHandlerApis(){
            // Load framework
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")) else { return }
        
            // Get a Swift function for MRMediaRemoteSendCommand
        guard let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) else { return }
        
        typealias MRMediaRemoteSendCommandFunction = @convention(c) (Int, AnyObject?) -> Void
        
        MrMediaRemoteSendCommandFunction = unsafeBitCast(MRMediaRemoteSendCommandPointer, to: MRMediaRemoteSendCommandFunction.self)

        guard let MRMediaRemoteSetElapsedTimePointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSetElapsedTime" as CFString) else { return }

        typealias MRMediaRemoteSetElapsedTimeFunction = @convention(c) (Double) -> Void
        MrMediaRemoteSetElapsedTimeFunction = unsafeBitCast(MRMediaRemoteSetElapsedTimePointer, to: MRMediaRemoteSetElapsedTimeFunction.self)
    }
    
    deinit {
        self.MrMediaRemoteSendCommandFunction = {_,_ in }
        self.MrMediaRemoteSetElapsedTimeFunction = { _ in }
    }
    
    func playPause() {
        if musicManager.isPlaying {
            MrMediaRemoteSendCommandFunction(2, nil)
        } else {
            MrMediaRemoteSendCommandFunction(0, nil)
        }
    }
    
    func nextTrack() {
            // Implement next track action
        MrMediaRemoteSendCommandFunction(4, nil)
    }
    
    func previousTrack() {
            // Implement previous track action
        MrMediaRemoteSendCommandFunction(5, nil)
    }

    func seekTrack(to time: TimeInterval) {
        MrMediaRemoteSetElapsedTimeFunction(time)
    }
}
