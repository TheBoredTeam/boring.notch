//
//  TidalController.swift
//  boringNotch
//
//  Created by YavuzAkbay on 2025-01-27.
//

import Foundation
import Combine
import SwiftUI

class TidalController: MediaControllerProtocol {
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.tidal.desktop"
    )
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }
    
    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var timelineUpdateTask: Task<Void, Never>?
    private var acceptingTidalStream: Bool = false
    
    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle?
    private let MRMediaRemoteSendCommandFunction: (@convention(c) (Int, AnyObject?) -> Void)?
    private let MRMediaRemoteSetElapsedTimeFunction: (@convention(c) (Double) -> Void)?
    private let MRMediaRemoteSetShuffleModeFunction: (@convention(c) (Int) -> Void)?
    private let MRMediaRemoteSetRepeatModeFunction: (@convention(c) (Int) -> Void)?
    
    //Constant for time between command and update
    let commandUpdateDelay: Duration = .milliseconds(25)
    
    // MARK: - Initialization
    init() {
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
            let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSendCommand" as CFString),
            let MRMediaRemoteSetElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetElapsedTime" as CFString),
            let MRMediaRemoteSetShuffleModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetShuffleMode" as CFString),
            let MRMediaRemoteSetRepeatModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetRepeatMode" as CFString)
            
        else { 
            assertionFailure("Failed to load MediaRemote framework functions")
            mediaRemoteBundle = nil
            MRMediaRemoteSendCommandFunction = nil
            MRMediaRemoteSetElapsedTimeFunction = nil
            MRMediaRemoteSetShuffleModeFunction = nil
            MRMediaRemoteSetRepeatModeFunction = nil
            return
        }

        mediaRemoteBundle = bundle
        MRMediaRemoteSendCommandFunction = unsafeBitCast(
            MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(
            MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        MRMediaRemoteSetShuffleModeFunction = unsafeBitCast(
            MRMediaRemoteSetShuffleModePointer, to: (@convention(c) (Int) -> Void).self)
        MRMediaRemoteSetRepeatModeFunction = unsafeBitCast(
            MRMediaRemoteSetRepeatModePointer, to: (@convention(c) (Int) -> Void).self)

        Task { await setupTidalObserver() }
    }
    
    deinit {
        streamTask?.cancel()
        timelineUpdateTask?.cancel()
        
        if let pipeHandler = self.pipeHandler {
            Task { await pipeHandler.close()
            }
        }
        
        if let process = self.process {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        self.process = nil
        self.pipeHandler = nil
    }
    
    // MARK: - Protocol Implementation
    func play() async {
        MRMediaRemoteSendCommandFunction?(0, nil)
        // Immediately update UI state
        var updatedState = self.playbackState
        updatedState.isPlaying = true
        self.playbackState = updatedState
    }
    
    func pause() async {
        MRMediaRemoteSendCommandFunction?(1, nil)
        // Immediately update UI state
        var updatedState = self.playbackState
        updatedState.isPlaying = false
        self.playbackState = updatedState
    }
    
    func togglePlay() async {
        MRMediaRemoteSendCommandFunction?(2, nil)
        // Immediately update UI state
        var updatedState = self.playbackState
        updatedState.isPlaying.toggle()
        self.playbackState = updatedState
    }
    
    func nextTrack() async {
        MRMediaRemoteSendCommandFunction?(4, nil)
    }
    
    func previousTrack() async {
        MRMediaRemoteSendCommandFunction?(5, nil)
    }
    
    func seek(to time: Double) async {
        MRMediaRemoteSetElapsedTimeFunction?(time)
        // Immediately update UI state for instant feedback
        var updatedState = self.playbackState
        updatedState.currentTime = time
        updatedState.lastUpdated = Date()
        self.playbackState = updatedState
    }
    
    func toggleShuffle() async {
        MRMediaRemoteSetShuffleModeFunction?(playbackState.isShuffled ? 3 : 1)
        playbackState.isShuffled.toggle()
    }
    
    func toggleRepeat() async {
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        MRMediaRemoteSetRepeatModeFunction?(newRepeatMode)
    }
    
    func isActive() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == playbackState.bundleIdentifier }
    }
    
    func updatePlaybackInfo() async {
        // This will be handled by the stream observer
    }
    
    // MARK: - Setup Methods
    private func setupTidalObserver() async {
        let process = Process()
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
        else {
            assertionFailure("Could not find mediaremote-adapter.pl script or framework path")
            return
        }
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, "stream", "--no-diff"]
        
        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = await pipeHandler.getPipe()
        
        self.process = process
        self.pipeHandler = pipeHandler

        do {
            try process.run()
            
            streamTask = Task { [weak self] in
                await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { update in
                    await self?.handleTidalUpdate(update)
                }
            }
        } catch {
            assertionFailure("Failed to start Tidal observer: \(error)")
        }
    }
    
    private func handleTidalUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? true

        // Ignore everything if the Tidal app is not running
        guard isActive() else {
            acceptingTidalStream = false
            stopTimelineUpdates()
            return
        }

        if let exactBundle = payload.bundleIdentifier {
            if exactBundle == "com.tidal.desktop" {
                acceptingTidalStream = true
            } else {
                acceptingTidalStream = false
                stopTimelineUpdates()
                return
            }
        } else {
            guard acceptingTidalStream else { return }
        }
        
        guard let title = payload.title, let artist = payload.artist,
              !title.isEmpty, !artist.isEmpty else {
            return
        }
        
        let lowercasedTitle = title.lowercased()
        let lowercasedArtist = artist.lowercased()
        
        if lowercasedTitle.contains("youtube") || 
           lowercasedArtist.contains("youtube") ||
           lowercasedTitle.contains("video") ||
           lowercasedTitle.contains("watch") ||
           lowercasedTitle.contains("youtu.be") ||
           lowercasedTitle.contains("youtube.com") {
            return
        }

        // Determine if the incoming payload signals a track change (based on new values)
        let previousTitle = self.playbackState.title
        let previousArtist = self.playbackState.artist
        let previousAlbum = self.playbackState.album
        let trackChanged = (payload.title != nil && payload.title != previousTitle)
            || (payload.artist != nil && payload.artist != previousArtist)
            || (payload.album != nil && payload.album != previousAlbum)
        
        var newPlaybackState = self.playbackState
        
        if let title = payload.title {
            newPlaybackState.title = title
        }
        
        if let artist = payload.artist {
            newPlaybackState.artist = artist
        }
        
        if let album = payload.album {
            newPlaybackState.album = album
        }
        
        if let duration = payload.duration {
            newPlaybackState.duration = duration
        }
        
        if let elapsedTime = payload.elapsedTime {
            newPlaybackState.currentTime = elapsedTime
        }
        
        if let shuffleMode = payload.shuffleMode {
            newPlaybackState.isShuffled = shuffleMode != 0
        }
        
        if let repeatMode = payload.repeatMode {
            newPlaybackState.repeatMode = RepeatMode(rawValue: repeatMode) ?? .off
        }
        
        if let artworkData = payload.artworkData {
            let trimmedData = artworkData.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = Data(base64Encoded: trimmedData) {
                newPlaybackState.artwork = data
            } else if let data = Data(base64Encoded: artworkData) {
                newPlaybackState.artwork = data
            } else {
                newPlaybackState.artwork = nil
            }
        } else if trackChanged {
            newPlaybackState.artwork = nil
            Task { [expectedTitle = newPlaybackState.title, expectedArtist = newPlaybackState.artist] in
                await self.fetchArtworkSnapshotIfMatches(expectedTitle: expectedTitle, expectedArtist: expectedArtist)
            }
        }
        
        if let dateString = payload.timestamp,
           let date = ISO8601DateFormatter().date(from: dateString) {
            newPlaybackState.lastUpdated = date
        } else {
            newPlaybackState.lastUpdated = Date()
        }
        
        if let playing = payload.playing {
            newPlaybackState.isPlaying = playing
        } else if let playbackRate = payload.playbackRate {
            newPlaybackState.isPlaying = playbackRate > 0.01
        } else if diff {
            newPlaybackState.isPlaying = self.playbackState.isPlaying
        } else {
            newPlaybackState.isPlaying = false
        }
        
        newPlaybackState.playbackRate = payload.playbackRate ?? (diff ? self.playbackState.playbackRate : 1.0)
        newPlaybackState.bundleIdentifier = "com.tidal.desktop"
        
        self.playbackState = newPlaybackState
        
        if acceptingTidalStream && newPlaybackState.isPlaying && newPlaybackState.duration > 0 {
            startTimelineUpdates()
        } else {
            stopTimelineUpdates()
        }
    }

    // MARK: - Snapshot artwork fetch
    private func fetchArtworkSnapshotIfMatches(expectedTitle: String, expectedArtist: String) async {
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
        else { return }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, "get"]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = try await readAll(from: pipe)

            // Try to decode either NowPlayingUpdate or NowPlayingPayload
            let decoder = JSONDecoder()
            var payload: NowPlayingPayload?
            if let update = try? decoder.decode(NowPlayingUpdate.self, from: data) {
                payload = update.payload
            } else if let direct = try? decoder.decode(NowPlayingPayload.self, from: data) {
                payload = direct
            }

            guard let payload = payload else { return }

            guard payload.bundleIdentifier == "com.tidal.desktop" else { return }
            
            guard let title = payload.title, let artist = payload.artist,
                  !title.isEmpty, !artist.isEmpty else { return }
            
            let lowercasedTitle = title.lowercased()
            let lowercasedArtist = artist.lowercased()
            
            if lowercasedTitle.contains("youtube") || 
               lowercasedArtist.contains("youtube") ||
               lowercasedTitle.contains("video") ||
               lowercasedTitle.contains("watch") ||
               lowercasedTitle.contains("youtu.be") ||
               lowercasedTitle.contains("youtube.com") {
                return
            }
            
            if title == expectedTitle && artist == expectedArtist,
               let b64 = payload.artworkData {
                let trimmed = b64.trimmingCharacters(in: .whitespacesAndNewlines)
                if let bytes = Data(base64Encoded: trimmed) ?? Data(base64Encoded: b64) {
                    var updated = self.playbackState
                    updated.artwork = bytes
                    self.playbackState = updated
                }
            }
        } catch {
            // Ignore snapshot errors
        }
    }

    private func readAll(from pipe: Pipe) async throws -> Data {
        let handle = pipe.fileHandleForReading
        var buffer = Data()
        while true {
            let chunk = try await handle.read(upToCount: 64 * 1024)
            guard let chunk = chunk, !chunk.isEmpty else { break }
            buffer.append(chunk)
        }
        return buffer
    }
    
    // MARK: - Timeline Management
    
    private func startTimelineUpdates() {
        timelineUpdateTask?.cancel()
        
        timelineUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                
                guard let self = self,
                      self.acceptingTidalStream,
                      self.playbackState.isPlaying,
                      self.playbackState.duration > 0 else { continue }
                
                let timeSinceLastUpdate = Date().timeIntervalSince(self.playbackState.lastUpdated)
                let estimatedCurrentTime = self.playbackState.currentTime + (timeSinceLastUpdate * self.playbackState.playbackRate)
                let newCurrentTime = max(0, min(estimatedCurrentTime, self.playbackState.duration))
                
                if abs(newCurrentTime - self.playbackState.currentTime) > 0.1 {
                    var updatedState = self.playbackState
                    updatedState.currentTime = newCurrentTime
                    updatedState.lastUpdated = Date()
                    self.playbackState = updatedState
                }
            }
        }
    }
    
    private func stopTimelineUpdates() {
        timelineUpdateTask?.cancel()
        timelineUpdateTask = nil
    }
}
