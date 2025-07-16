//
//  NowPlayingController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Combine
import AppKit
import Foundation

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    // Stub for now to conform with ControllerProtocol
    func updatePlaybackInfo() {}

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.apple.Music"
    )

    var playbackStatePublisher: Published<PlaybackState>.Publisher { $playbackState }
    private var cancellables = Set<AnyCancellable>()
    private var lastMusicItem: (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?)?

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void

    private var process: Process?
    private let pipe = Pipe()
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
                bundle, "MRMediaRemoteSetElapsedTime" as CFString)
        else { return nil }

        mediaRemoteBundle = bundle
        MRMediaRemoteSendCommandFunction = unsafeBitCast(
            MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(
            MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)

        setupNowPlayingObserver()
        updatePlaybackInfo()
    }

    deinit {
        process?.terminate()
        pipe.fileHandleForReading.readabilityHandler = nil
    }

    // MARK: - Protocol Implementation
    func play() {
        MRMediaRemoteSendCommandFunction(0, nil)
    }

    func pause() {
        MRMediaRemoteSendCommandFunction(1, nil)
    }

    func togglePlay() {
        MRMediaRemoteSendCommandFunction(2, nil)
    }

    func nextTrack() {
        MRMediaRemoteSendCommandFunction(4, nil)
    }

    func previousTrack() {
        MRMediaRemoteSendCommandFunction(5, nil)
    }

    func seek(to time: Double) {
        MRMediaRemoteSetElapsedTimeFunction(time)
    }

    func isActive() -> Bool {
        return true
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

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let chunk = String(data: data, encoding: .utf8) {
                self.buffer.append(chunk)
                while let range = self.buffer.range(of: "\n") {
                    let line = String(self.buffer[..<range.lowerBound])
                    self.buffer = String(self.buffer[range.upperBound...])
                    if !line.isEmpty {
                        self.handleAdapterUpdate(line)
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

        DispatchQueue.main.async {
            self.playbackState.title = payload["title"] as? String ?? self.playbackState.title
            self.playbackState.artist = payload["artist"] as? String ?? self.playbackState.artist
            self.playbackState.album = payload["album"] as? String ?? self.playbackState.album
            self.playbackState.duration = payload["duration"] as? Double ?? self.playbackState.duration
            self.playbackState.currentTime = payload["elapsedTime"] as? Double ?? self.playbackState.currentTime
            if let artworkDataString = payload["artworkData"] as? String {
                self.playbackState.artwork = Data(
                    base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            if let dateString = payload["timestamp"] as? String,
               let date = ISO8601DateFormatter().date(from: dateString) {
                self.playbackState.lastUpdated = date
            }
            self.playbackState.playbackRate = payload["playbackRate"] as? Double ?? self.playbackState.playbackRate
            self.playbackState.isPlaying = payload["playing"] as? Bool ?? self.playbackState.isPlaying
            self.playbackState.bundleIdentifier =
                payload["parentBundleIdentifier"] as? String ?? payload["bundleIdentifier"]
                as? String ?? self.playbackState.bundleIdentifier
        }
    }
}
