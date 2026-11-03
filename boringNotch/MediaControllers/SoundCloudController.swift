//
//  SoundCloudController.swift
//  boringNotch
//
//  Created by Kylian Tranchet on 2026-11-03.
//

import Foundation
import Combine
import SwiftUI

/// Controls the SoundCloud web player (soundcloud.com) running in a browser tab.
/// SoundCloud has no native macOS app, so playback is read and driven by running
/// JavaScript in the tab through AppleScript. The browser must allow it
/// (Safari: Develop > Allow JavaScript from Apple Events,
/// Chromium: View > Developer > Allow JavaScript from Apple Events).
class SoundCloudController: MediaControllerProtocol {
    private struct Browser {
        let bundleIdentifier: String
        let isSafari: Bool
    }

    private static let supportedBrowsers: [Browser] = [
        Browser(bundleIdentifier: "com.apple.Safari", isSafari: true),
        Browser(bundleIdentifier: "com.google.Chrome", isSafari: false),
        Browser(bundleIdentifier: "company.thebrowser.Browser", isSafari: false),
        Browser(bundleIdentifier: "com.brave.Browser", isSafari: false),
        Browser(bundleIdentifier: "com.microsoft.edgemac", isSafari: false),
    ]

    private struct PlayerInfo: Decodable {
        let title: String
        let artist: String
        let isPlaying: Bool
        let currentTime: Double
        let duration: Double
        let isShuffled: Bool
        let repeatMode: String
        let artworkURL: String
    }

    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.apple.Safari"
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool { false }

    var supportsFavorite: Bool { false }

    private var pollingTask: Task<Void, Never>?

    // Constant for time between command and update
    private let commandUpdateDelay: Duration = .milliseconds(150)
    private let pollInterval: Duration = .seconds(1)

    private var lastArtworkURL: String?
    private var artworkFetchTask: Task<Void, Never>?

    init() {
        startPolling()
    }

    deinit {
        pollingTask?.cancel()
        artworkFetchTask?.cancel()
    }

    private func startPolling() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.isActive() {
                    await self.updatePlaybackInfo()
                }
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    // MARK: - Protocol Implementation
    func setFavorite(_ favorite: Bool) async {
        // Not supported
    }

    func play() async {
        await executeAndRefresh("var b=q('.playControls__play');if(b&&!b.classList.contains('playing'))b.click();")
    }

    func pause() async {
        await executeAndRefresh("var b=q('.playControls__play');if(b&&b.classList.contains('playing'))b.click();")
    }

    func togglePlay() async { await executeAndRefresh("click('.playControls__play');") }
    func nextTrack() async { await executeAndRefresh("click('.skipControl__next');") }
    func previousTrack() async { await executeAndRefresh("click('.skipControl__previous');") }
    func toggleShuffle() async { await executeAndRefresh("click('.shuffleControl');") }
    func toggleRepeat() async { await executeAndRefresh("click('.repeatControl');") }

    func seek(to time: Double) async {
        let duration = playbackState.duration
        guard duration > 0 else { return }
        let ratio = max(0, min(1, time / duration))
        // The timeline reacts to mouse events, so simulate a click at the target position
        await executeAndRefresh("""
        var w=q('.playbackTimeline__progressWrapper');
        if(w){var r=w.getBoundingClientRect();var o={bubbles:true,cancelable:true,view:window,clientX:r.left+r.width*\(ratio),clientY:r.top+r.height/2,button:0};
        ['mousedown','mousemove','mouseup','click'].forEach(function(e){w.dispatchEvent(new MouseEvent(e,o));});}
        """)
    }

    func setVolume(_ level: Double) async {
        // Not supported
    }

    func isActive() -> Bool {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Self.supportedBrowsers.contains { running.contains($0.bundleIdentifier) }
    }

    func updatePlaybackInfo() async {
        guard let tabResult = await runInSoundCloudTab("""
        var t=q('.playbackSoundBadge__titleLink');
        if(!t)return '';
        var a=q('.playbackSoundBadge__lightLink');
        var p=q('.playControls__play');
        var w=q('.playbackTimeline__progressWrapper');
        var s=q('.shuffleControl');
        var r=q('.repeatControl');
        var i=q('.playControls .playbackSoundBadge .sc-artwork');
        var bg=i?getComputedStyle(i).backgroundImage:'';
        var u=bg.indexOf('url(')>=0?bg.slice(bg.indexOf('(')+1,bg.lastIndexOf(')')).replace(/['"]/g,''):'';
        var secs=function(sel){var e=q(sel+' span[aria-hidden]');if(!e)return 0;return e.textContent.trim().split(':').reduce(function(acc,v){return acc*60+(parseInt(v,10)||0);},0);};
        var cur=w&&w.getAttribute('aria-valuenow')?parseFloat(w.getAttribute('aria-valuenow')):secs('.playbackTimeline__timePassed');
        var dur=w&&w.getAttribute('aria-valuemax')?parseFloat(w.getAttribute('aria-valuemax')):secs('.playbackTimeline__duration');
        return JSON.stringify({
          title:(t.getAttribute('title')||t.textContent||'').trim(),
          artist:a?(a.getAttribute('title')||a.textContent||'').trim():'',
          isPlaying:!!(p&&p.classList.contains('playing')),
          currentTime:cur||0,
          duration:dur||0,
          isShuffled:!!(s&&s.classList.contains('m-shuffling')),
          repeatMode:r?(r.classList.contains('m-one')?'one':r.classList.contains('m-all')?'all':'off'):'off',
          artworkURL:u.replace(/-t\\d+x\\d+\\./,'-t500x500.')
        });
        """),
            let data = tabResult.1.data(using: .utf8),
            let info = try? JSONDecoder().decode(PlayerInfo.self, from: data)
        else { return }

        let repeatMode: RepeatMode
        switch info.repeatMode {
        case "one": repeatMode = .one
        case "all": repeatMode = .all
        default: repeatMode = .off
        }

        var state = PlaybackState(
            bundleIdentifier: tabResult.0,
            isPlaying: info.isPlaying,
            title: info.title,
            artist: info.artist,
            album: "SoundCloud",
            currentTime: info.currentTime,
            duration: info.duration,
            playbackRate: 1,
            isShuffled: info.isShuffled,
            repeatMode: repeatMode,
            lastUpdated: Date(),
            artwork: nil
        )

        let artworkURL = info.artworkURL
        if artworkURL == lastArtworkURL, let existingArtwork = self.playbackState.artwork {
            state.artwork = existingArtwork
        }

        await MainActor.run { self.playbackState = state }

        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            guard artworkURL != lastArtworkURL || state.artwork == nil else { return }
            artworkFetchTask?.cancel()

            let currentState = state

            artworkFetchTask = Task {
                do {
                    let data = try await ImageService.shared.fetchImageData(from: url)

                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        var updatedState = currentState
                        updatedState.artwork = data
                        self.playbackState = updatedState
                        self.lastArtworkURL = artworkURL
                        self.artworkFetchTask = nil
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.artworkFetchTask = nil
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    private func executeAndRefresh(_ body: String) async {
        _ = await runInSoundCloudTab("\(body) return 'ok';")
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }

    /// Runs `body` as a JavaScript function body in the first soundcloud.com tab that has
    /// an active player, and returns the hosting browser's bundle identifier with the result.
    private func runInSoundCloudTab(_ body: String) async -> (String, String)? {
        let javaScript = """
        (function(){var q=function(s){return document.querySelector(s);};\
        var click=function(s){var e=q(s);if(e)e.click();};\
        if(!q('.playControls__play'))return '';\(body)})()
        """
        let escaped = javaScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")

        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for browser in Self.supportedBrowsers where running.contains(browser.bundleIdentifier) {
            let runCommand = browser.isSafari
                ? "do JavaScript \"\(escaped)\" in t"
                : "execute t javascript \"\(escaped)\""
            let script = """
            tell application id "\(browser.bundleIdentifier)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t as text) contains "soundcloud.com" then
                            try
                                set r to \(runCommand)
                                if r is not missing value and r is not "" then return r
                            end try
                        end if
                    end repeat
                end repeat
            end tell
            return ""
            """
            if let result = try? await AppleScriptHelper.execute(script)?.stringValue, !result.isEmpty {
                return (browser.bundleIdentifier, result)
            }
        }
        return nil
    }
}
