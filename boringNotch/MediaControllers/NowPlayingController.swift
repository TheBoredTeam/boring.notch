//
//  NowPlayingController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import AppKit
import Combine
import Foundation

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    // Stub for now to conform with ControllerProtocol
    func updatePlaybackInfo() {}

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.apple.Music"
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }
    private var lastMusicItem:
        (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?)?

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void

    private var process: Process?
    private var pipe: Pipe?
    private var buffer = ""

    // MARK: - Initialization
    init?() {
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
            
        else { return nil }

        mediaRemoteBundle = bundle
        MRMediaRemoteSendCommandFunction = unsafeBitCast(
            MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(
            MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        MRMediaRemoteSetShuffleModeFunction = unsafeBitCast(
            MRMediaRemoteSetShuffleModePointer, to: (@convention(c) (Int) -> Void).self)
        MRMediaRemoteSetRepeatModeFunction = unsafeBitCast(
            MRMediaRemoteSetRepeatModePointer, to: (@convention(c) (Int) -> Void).self)

        setupNowPlayingObserver()
        updatePlaybackInfo()
    }

    deinit {
        if let process = self.process {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        if let pipe = self.pipe {
            pipe.fileHandleForReading.closeFile()
            pipe.fileHandleForWriting.closeFile()
        }

        self.process = nil
        self.pipe = nil
    }

    // MARK: - Protocol Implementation
    func play() async {
        MRMediaRemoteSendCommandFunction(0, nil)
    }

    func pause() async {
        MRMediaRemoteSendCommandFunction(1, nil)
    }

    func togglePlay() async {
        MRMediaRemoteSendCommandFunction(2, nil)
    }

    func nextTrack() async {
        MRMediaRemoteSendCommandFunction(4, nil)
    }

    func previousTrack() async {
        MRMediaRemoteSendCommandFunction(5, nil)
    }

    func seek(to time: Double) async {
        MRMediaRemoteSetElapsedTimeFunction(time)
    }

    func isActive() -> Bool {
        return true
    }
    
    func toggleShuffle() async {
        // MRMediaRemoteSendCommandFunction(6, nil)
        MRMediaRemoteSetShuffleModeFunction(playbackState.isShuffled ? 3 : 1)
        playbackState.isShuffled.toggle()
    }
    
    func toggleRepeat() async {
        // MRMediaRemoteSendCommandFunction(7, nil)
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
    }
    
    // MARK: - Setup Methods
    private func setupNowPlayingObserver() {
        let process = Process()
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
        else {
            assertionFailure("Could not find mediaremote-adapter.pl script or framework path")
            return
        }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, "stream"]
        let pipe = Pipe()
        process.standardOutput = pipe
        self.process = process
        self.pipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let chunk = String(data: data, encoding: .utf8) {
                self?.buffer.append(chunk)
                while let range = self?.buffer.range(of: "\n") {
                    let line = String(self?.buffer[..<range.lowerBound] ?? "")
                    self?.buffer = String(self?.buffer[range.upperBound...] ?? "")
                    if !line.isEmpty {
                        self?.handleAdapterUpdate(line)
                    }
                }
            }
        }

        do {
            try process.run()
        } catch {
            assertionFailure("Failed to launch mediaremote-adapter.pl: \(error)")
        }
    }

    // MARK: - Update Methods
    private func handleAdapterUpdate(_ jsonLine: String) {
        guard let data = jsonLine.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = object["payload"] as? [String: Any]
        else { return }

        let diff = object["diff"] as? Bool ?? false

        var newPlaybackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)
        
        newPlaybackState.title = payload["title"] as? String ?? (diff ? self.playbackState.title : "")
        newPlaybackState.artist = payload["artist"] as? String ?? (diff ? self.playbackState.artist : "")
        newPlaybackState.album = payload["album"] as? String ?? (diff ? self.playbackState.album : "")
        newPlaybackState.duration = payload["duration"] as? Double ?? (diff ? self.playbackState.duration : 0)
        newPlaybackState.currentTime = payload["elapsedTime"] as? Double ?? (diff ? self.playbackState.currentTime : 0)
        
        if let shuffleMode = payload["shuffleMode"] as? Int {
            newPlaybackState.isShuffled = shuffleMode != 1
        } else if !diff {
            newPlaybackState.isShuffled = false
        }
        if let repeatModeValue = payload["repeatMode"] as? Int {
            newPlaybackState.repeatMode = RepeatMode(rawValue: repeatModeValue) ?? .off
        } else if !diff {
            newPlaybackState.repeatMode = .off
        }

        if let artworkDataString = payload["artworkData"] as? String {
            newPlaybackState.artwork = Data(
                base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else if !diff {
            newPlaybackState.artwork = nil
        }

        if let dateString = payload["timestamp"] as? String,
           let date = ISO8601DateFormatter().date(from: dateString) {
            newPlaybackState.lastUpdated = date
        }

        newPlaybackState.playbackRate = payload["playbackRate"] as? Double ?? (diff ? self.playbackState.playbackRate : 1.0)
        newPlaybackState.isPlaying = payload["playing"] as? Bool ?? (diff ? self.playbackState.isPlaying : false)
        newPlaybackState.bundleIdentifier = (
            payload["parentApplicationBundleIdentifier"] as? String ??
            payload["bundleIdentifier"] as? String ??
            (diff ? self.playbackState.bundleIdentifier : "")
        )
        
        self.playbackState = newPlaybackState
    }
}
