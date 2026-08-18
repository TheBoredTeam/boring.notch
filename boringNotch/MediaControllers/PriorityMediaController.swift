//
//  PriorityMediaController.swift
//  boringNotch
//
//  Composite media controller over an ordered priority list of sources. It surfaces whichever
//  enabled source is audibly playing, preferring higher-priority sources, and transparently
//  forwards commands to that live source. Generic "Now Playing" is just another entry (kept last
//  by convention); when nothing is live the last shown state is frozen rather than blanked.
//

import AppKit
import Combine
import Foundation

/// Threading: internal state (the live-index pointer, the debounce work item, the cached child
/// states) is *written* only on the main queue — the Combine sinks use `.receive(on: .main)`, the
/// workspace observers use `queue: .main`, and the debounced flip runs via `DispatchQueue.main`.
/// The `children` array is an immutable `let`, so the async command forwarders (play/pause/…) that
/// run from background Tasks only ever read immutable references plus `liveIndex` (a trivial `Int?`).
/// That single unsynchronized read is deliberately benign: a read that races the sub-second
/// debounced flip at worst routes one command to the just-previous child and self-corrects on the
/// next state update. `childStates` is never read off-main. To change the source list, MusicManager
/// builds a *new* controller and swaps it — this object is never mutated in place. `deinit` may run
/// off the main queue (an in-flight command Task can hold the last reference), so its teardown is
/// limited to thread-safe calls (`DispatchWorkItem.cancel` + `NotificationCenter.removeObserver`).
final class PriorityMediaController: ObservableObject, MediaControllerProtocol {

    // MARK: - Source selection (pure)

    /// Precedence rule — strict priority, "prefer whatever is actually playing":
    /// 1. first source that is active AND playing   (highest-priority audible source)
    /// 2. else first source that is active          (highest-priority running/paused source)
    /// 3. else nil                                  (nothing live -> caller freezes last state)
    ///
    /// `active`/`playing` are parallel arrays in priority order. Because generic Now Playing is
    /// pinned last and reports `isActive() == true`, a running app source always outranks it, and a
    /// dedicated controller outranks Now Playing mirroring the same app whenever the app is playing.
    static func selectLiveIndex(active: [Bool], playing: [Bool]) -> Int? {
        for i in active.indices where active[i] && playing[i] { return i }
        for i in active.indices where active[i] { return i }
        return nil
    }

    // MARK: - Published state

    @Published private var playbackState: PlaybackState = PlaybackState(bundleIdentifier: "")

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    // MARK: - Children (immutable)

    private let children: [any MediaControllerProtocol]
    private var childStates: [PlaybackState]
    private(set) var liveIndex: Int?

    private var live: (any MediaControllerProtocol)? {
        guard let i = liveIndex, children.indices.contains(i) else { return nil }
        return children[i]
    }

    // MARK: - Plumbing

    private var cancellables = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var flipWorkItem: DispatchWorkItem?
    /// Debounce so transient app launch/quit/track-change blips don't thrash the source.
    private let flipDebounce: TimeInterval = 0.8

    // MARK: - Init

    /// - Parameter children: sources in priority order (earlier == higher). Must be non-empty;
    ///   MusicManager guarantees that and uses a bare controller (no composite) for a single source.
    init(children: [any MediaControllerProtocol]) {
        self.children = children
        self.childStates = children.map { _ in PlaybackState(bundleIdentifier: "") }
        // Seed the live index from what's currently active (states are still empty, so this is the
        // "first active" tier). Avoids a debounce-length blank on first display.
        self.liveIndex = Self.selectLiveIndex(
            active: children.map { $0.isActive() },
            playing: children.map { _ in false }
        )

        // @Published publishers re-emit their current value to new subscribers; delivered on the
        // next main run-loop iteration, this seeds childStates and triggers the first arbitration.
        for (index, child) in children.enumerated() {
            child.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self, self.childStates.indices.contains(index) else { return }
                    self.childStates[index] = state
                    self.recomputeAndRepublish()
                }
                .store(in: &cancellables)
        }

        setupWorkspaceObservers()
    }

    deinit {
        flipWorkItem?.cancel()
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { nc.removeObserver($0) }
    }

    // MARK: - Arbitration

    /// App launch/quit makes app sources go silent without publishing, so observe the workspace
    /// directly to notice a chosen app appearing/disappearing (blanket — any app, we re-arbitrate).
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

    private func currentDesiredIndex() -> Int? {
        Self.selectLiveIndex(
            active: children.map { $0.isActive() },
            playing: childStates.map { $0.isPlaying }
        )
    }

    private func recomputeAndRepublish() {
        guard let desired = currentDesiredIndex() else {
            // Nothing active: keep the last live source (freeze). Cancel any pending flip.
            flipWorkItem?.cancel()
            flipWorkItem = nil
            publishCurrentLive()
            return
        }

        if desired == liveIndex {
            // No flip needed: cancel any pending opposite flip and surface the live state now.
            flipWorkItem?.cancel()
            flipWorkItem = nil
            publishCurrentLive()
            return
        }

        if liveIndex == nil {
            // No current live source to keep showing: adopt the desired one immediately (no debounce).
            liveIndex = desired
            flipWorkItem?.cancel()
            flipWorkItem = nil
            publishCurrentLive()
            return
        }

        // Promote immediately (no debounce) when the current live source isn't playing but the desired
        // one is: there's no thrash risk going from silence to audio, and it honors "prefer whatever is
        // playing" — avoids a debounce-long window showing a paused higher-priority source (e.g. at startup).
        if let current = liveIndex, childStates.indices.contains(current), !childStates[current].isPlaying,
           childStates.indices.contains(desired), childStates[desired].isPlaying {
            liveIndex = desired
            flipWorkItem?.cancel()
            flipWorkItem = nil
            publishCurrentLive()
            return
        }

        // Flip between two real sources: schedule once, debounced. Keep showing current until it commits.
        if flipWorkItem == nil {
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if let desiredNow = self.currentDesiredIndex() {
                    self.liveIndex = desiredNow
                }
                self.flipWorkItem = nil
                self.publishCurrentLive()
            }
            flipWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + flipDebounce, execute: item)
        }
        publishCurrentLive()
    }

    private func publishCurrentLive() {
        guard let i = liveIndex, childStates.indices.contains(i) else { return }  // nil -> freeze last shown
        let candidate = childStates[i]
        // Freeze-last also when the live source is *contentless*: the always-active Now Playing child
        // can momentarily hold an empty state (e.g. after a MediaRemote clear) and, because it never
        // reports inactive, a transient blip on a higher-priority source can promote to it. Publishing
        // that empty state would blank the notch over a still-playing track. Keep the last
        // real state instead; a genuine pause still carries bundle id + title and publishes normally.
        if candidate.bundleIdentifier.isEmpty && candidate.title.isEmpty { return }
        playbackState = candidate
    }

    // MARK: - MediaControllerProtocol (capabilities reflect the live child)

    var channelPolicy: MediaChannelPolicy { live?.channelPolicy ?? .allSupported }

    /// The composite is always serviceable: even with nothing live it holds the last state.
    func isActive() -> Bool { true }

    func updatePlaybackInfo() async { await live?.updatePlaybackInfo() }
    func forceRefresh() async { await live?.forceRefresh() }

    func play() async { await live?.play() }
    func pause() async { await live?.pause() }
    func togglePlay() async { await live?.togglePlay() }
    func nextTrack() async { await live?.nextTrack() }
    func previousTrack() async { await live?.previousTrack() }
    func seek(to time: Double) async { await live?.seek(to: time) }
    func toggleShuffle() async { await live?.toggleShuffle() }
    func toggleRepeat() async { await live?.toggleRepeat() }
    func setVolume(_ level: Double) async { await live?.setVolume(level) }
    func setFavorite(_ favorite: Bool) async { await live?.setFavorite(favorite) }
}
