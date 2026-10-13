//
//  NowPlayingController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import AppKit
import Combine
import Foundation

@MainActor
final class NowPlayingController: NowPlayingRuntimeControlling {
    func updatePlaybackInfo() async {
        await fetchFavoriteStateIfSupported()
    }

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: ""
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == MediaAppBundleID.appleMusic || bundleID == MediaAppBundleID.spotify
    }

    var supportsFavorite: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == MediaAppBundleID.appleMusic
    }

    func setFavorite(_ favorite: Bool) async {
        let bundleID = playbackState.bundleIdentifier

        if bundleID == MediaAppBundleID.appleMusic {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: MediaAppBundleID.appleMusic)
            if !runningApps.isEmpty {
                let script = """
                tell application "Music"
                    try
                        set favorited of current track to \(favorite ? "true" : "false")
                    end try
                end tell
                """
                try? await AppleScriptHelper.executeVoid(script)
            }
        }

        // Update the favorite state locally and fetch updated info
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void
    private let adapterScriptURL: URL
    private let adapterFrameworkPath: String

    let runtimeFailures: AsyncStream<Void>
    private let runtimeFailureContinuation: AsyncStream<Void>.Continuation

    private var streamSession: NowPlayingStreamSession?

    // MARK: - Initialization
    init() throws {
        let resources = try NowPlayingResources.load()

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
            throw NowPlayingError.unavailable
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
        adapterScriptURL = resources.adapterScriptURL
        adapterFrameworkPath = resources.adapterFrameworkPath

        let runtimeFailureChannel = AsyncStream.makeStream(of: Void.self)
        runtimeFailures = runtimeFailureChannel.stream
        runtimeFailureContinuation = runtimeFailureChannel.continuation
    }

    deinit {
        if let streamSession {
            Task { @MainActor in
                streamSession.stop()
            }
        }
        runtimeFailureContinuation.finish()
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
        MRMediaRemoteSetShuffleModeFunction(playbackState.isShuffled ? 1 : 3)
        playbackState.isShuffled.toggle()
    }

    func toggleRepeat() async {
        // MRMediaRemoteSendCommandFunction(7, nil)
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
    }

    func setVolume(_ level: Double) async {
        // MediaRemote framework doesn't provide direct volume control for the active audio session
        // As a workaround, try to control the currently active music app directly
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)

        let bundleID = playbackState.bundleIdentifier
        if !bundleID.isEmpty {
            if bundleID == MediaAppBundleID.appleMusic {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: MediaAppBundleID.appleMusic)
                if !runningApps.isEmpty {
                    let script = "tell application \"Music\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            } else if bundleID == MediaAppBundleID.spotify {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: MediaAppBundleID.spotify)
                if !runningApps.isEmpty {
                    let script = "tell application \"Spotify\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            }
        }

        playbackState.volume = clampedLevel
    }

    // MARK: - Runtime Stream Lifecycle
    func startRuntimeStream() {
        guard streamSession == nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [adapterScriptURL.path, adapterFrameworkPath, "stream", "--no-diff"]

        let session = NowPlayingStreamSession(
            process: process,
            onUpdate: { [weak self] update in
                await self?.handleAdapterUpdate(update)
            },
            onFailure: { [weak self] in
                guard let self else { return }
                self.streamSession = nil
                self.runtimeFailureContinuation.yield()
            }
        )
        streamSession = session
        session.start()
    }

    func stopRuntimeStream() {
        let session = streamSession
        streamSession = nil
        session?.stop()
    }

    // MARK: - Update Methods
    private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? false

        var newPlaybackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)
        let resolvedBundleIdentifier = (
            payload.parentApplicationBundleIdentifier ??
            payload.bundleIdentifier ??
            (diff ? self.playbackState.bundleIdentifier : "")
        )
        let captureBundleFallbackIdentifiers: [String]
        if diff {
            captureBundleFallbackIdentifiers =
                resolvedBundleIdentifier != self.playbackState.bundleIdentifier
                ? [resolvedBundleIdentifier]
                : self.playbackState.effectiveAudioCaptureBundleIdentifiers
        } else {
            captureBundleFallbackIdentifiers = [resolvedBundleIdentifier]
        }
        let captureBundleIdentifiers = Self.audioCaptureBundleIdentifiers(
            sourceBundleIdentifier: payload.bundleIdentifier,
            fallbackBundleIdentifiers: captureBundleFallbackIdentifiers
        )

        newPlaybackState = update.applying(to: playbackState)
        newPlaybackState.audioCaptureBundleIdentifiers = captureBundleIdentifiers


        self.playbackState = newPlaybackState
    }

    private func fetchFavoriteStateIfSupported() async {
        guard playbackState.bundleIdentifier == MediaAppBundleID.appleMusic else { return }

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: MediaAppBundleID.appleMusic)
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application "Music"
            try
                return favorited of current track
            on error
                return false
            end try
        end tell
        """
        if let result = try? await AppleScriptHelper.execute(script) {
            var updated = playbackState
            updated.isFavorite = result.booleanValue
            playbackState = updated
        }
    }
}

private extension NowPlayingController {
    static func audioCaptureBundleIdentifiers(
        sourceBundleIdentifier: String?,
        fallbackBundleIdentifiers: [String]
    ) -> [String] {
        let preferred = sourceBundleIdentifier.map { [$0] } ?? fallbackBundleIdentifiers
        return preferred.normalizedBundleIdentifiers
    }
}
