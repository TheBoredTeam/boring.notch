//
//  FallbackMediaController.swift
//  boringNotch
//
//  Composite media controller: shows the user's chosen app-specific source when it is the
//  audible source, and transparently falls back to the generic Now Playing source otherwise.
//

import AppKit
import Combine
import Foundation

/// Threading: this controller's internal state (the live-source pointer, the debounce work item,
/// the cached child states) is *written* only on the main queue — the Combine sinks use
/// `.receive(on: .main)`, the workspace observers use `queue: .main`, and the debounced flip runs
/// via `DispatchQueue.main`. The async command forwarders (play/pause/seek/…) may *read* `liveSource`
/// from a background Task, because MusicManager dispatches control commands from detached Tasks. That
/// read/write is deliberately left unsynchronized: `Source` is a trivial two-case value, so a read
/// that races the sub-second debounced flip at worst routes a single command to the just-previous
/// child and self-corrects on the next state update. Create and release on the main queue so
/// `deinit`'s teardown (which does not re-dispatch) is race-free.
final class FallbackMediaController: ObservableObject, MediaControllerProtocol {

    // MARK: - Source selection (pure)

    enum Source: Equatable { case primary, nowPlaying }

    /// Precedence rule — "prefer whatever is actually playing":
    /// 1. chosen app running AND playing            -> primary  (richer controls)
    /// 2. else something is playing via Now Playing -> nowPlaying
    /// 3. else chosen app running (paused/idle)     -> primary  (show its paused state)
    /// 4. else                                      -> nowPlaying
    ///
    /// Truth table (P=primaryActive, p=primaryPlaying, n=nowPlayingPlaying):
    ///   P=1 p=1 n=*  -> primary
    ///   P=1 p=0 n=1  -> nowPlaying   (chosen open+paused, audio elsewhere)
    ///   P=1 p=0 n=0  -> primary      (chosen open+paused, nothing else)
    ///   P=0  *  n=1  -> nowPlaying
    ///   P=0  *  n=0  -> nowPlaying    (chosen closed, nothing playing)
    static func selectLive(primaryActive: Bool, primaryPlaying: Bool, nowPlayingPlaying: Bool) -> Source {
        if primaryActive && primaryPlaying { return .primary }
        if nowPlayingPlaying { return .nowPlaying }
        if primaryActive { return .primary }
        return .nowPlaying
    }

    // MARK: - Published state

    @Published private var playbackState: PlaybackState = PlaybackState(bundleIdentifier: "")

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    // MARK: - Children

    private let primary: any MediaControllerProtocol
    private let nowPlaying: NowPlayingController

    private var primaryState: PlaybackState = PlaybackState(bundleIdentifier: "")
    private var nowPlayingState: PlaybackState = PlaybackState(bundleIdentifier: "")
    private(set) var liveSource: Source = .primary

    private var live: any MediaControllerProtocol {
        liveSource == .primary ? primary : nowPlaying
    }

    // MARK: - Plumbing

    private var cancellables = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var flipWorkItem: DispatchWorkItem?
    /// Debounce so transient app launch/quit/track-change blips don't thrash the source.
    private let flipDebounce: TimeInterval = 0.8

    // MARK: - Init

    init(primary: any MediaControllerProtocol, nowPlaying: NowPlayingController) {
        self.primary = primary
        self.nowPlaying = nowPlaying

        // @Published publishers re-emit their current value to new subscribers; delivered on
        // the next main run-loop iteration (via .receive(on:)), this seeds primaryState /
        // nowPlayingState and triggers the first arbitration.
        primary.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.primaryState = state
                self?.recomputeAndRepublish()
            }
            .store(in: &cancellables)

        nowPlaying.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.nowPlayingState = state
                self?.recomputeAndRepublish()
            }
            .store(in: &cancellables)

        setupWorkspaceObservers()
    }

    deinit {
        flipWorkItem?.cancel()
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { nc.removeObserver($0) }
    }

    // MARK: - Arbitration

    /// App launch/quit makes Apple Music / Spotify go silent without publishing, so observe the
    /// workspace directly to notice the chosen app appearing/disappearing.
    private func setupWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            let obs = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.recomputeAndRepublish()
            }
            workspaceObservers.append(obs)
        }
    }

    private func recomputeAndRepublish() {
        let desired = Self.selectLive(
            primaryActive: primary.isActive(),
            primaryPlaying: primaryState.isPlaying,
            nowPlayingPlaying: nowPlayingState.isPlaying
        )

        if desired == liveSource {
            // No flip needed: cancel any pending opposite flip and surface the live source's latest state now.
            flipWorkItem?.cancel()
            flipWorkItem = nil
            publishCurrentLive()
            return
        }

        // Flip wanted: schedule it once, debounced. Keep showing the current source until it commits.
        if flipWorkItem == nil {
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.liveSource = Self.selectLive(
                    primaryActive: self.primary.isActive(),
                    primaryPlaying: self.primaryState.isPlaying,
                    nowPlayingPlaying: self.nowPlayingState.isPlaying
                )
                self.flipWorkItem = nil
                self.publishCurrentLive()
            }
            flipWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + flipDebounce, execute: item)
        }
        publishCurrentLive()
    }

    private func publishCurrentLive() {
        playbackState = (liveSource == .primary) ? primaryState : nowPlayingState
    }

    // MARK: - MediaControllerProtocol (capabilities reflect the live child)

    var channelPolicy: MediaChannelPolicy { live.channelPolicy }

    /// The composite is always serviceable (Now Playing is the always-available floor).
    func isActive() -> Bool { true }

    func updatePlaybackInfo() async { await live.updatePlaybackInfo() }
    func forceRefresh() async { await live.forceRefresh() }

    func play() async { await live.play() }
    func pause() async { await live.pause() }
    func togglePlay() async { await live.togglePlay() }
    func nextTrack() async { await live.nextTrack() }
    func previousTrack() async { await live.previousTrack() }
    func seek(to time: Double) async { await live.seek(to: time) }
    func toggleShuffle() async { await live.toggleShuffle() }
    func toggleRepeat() async { await live.toggleRepeat() }
    func setVolume(_ level: Double) async { await live.setVolume(level) }
    func setFavorite(_ favorite: Bool) async { await live.setFavorite(favorite) }
}
