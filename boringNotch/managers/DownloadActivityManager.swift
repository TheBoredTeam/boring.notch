//
//  DownloadActivityManager.swift
//  boringNotch
//

import Combine
import Defaults
import Foundation

/// Shows an activity in the notch while files are downloading.
///
/// Built on `Progress.addSubscriber(forFileURL:withPublishingHandler:)`, the public
/// Foundation publish/subscribe mechanism the Dock itself uses to draw download progress on
/// the Downloads stack. Subscribing once to the Downloads folder delivers a live `Progress`
/// proxy for every download landing in it, so there is no polling, no directory scanning and
/// no timer anywhere in this file — the system pushes updates to us.
///
/// ## Limitations
/// - **The publishing process cannot be identified.** `NSProgress` carries no reference to
///   whoever published it, and there is no public API to recover one. The activity therefore
///   shows the file's own type icon rather than an app icon.
/// - Only items *directly contained* in a watched folder are reported; the API does not
///   recurse. Only the user's Downloads folder is watched, so a download saved elsewhere is
///   invisible to us.
/// - Coverage depends on the downloading app opting in by calling `publish()`. Apps that
///   never publish cannot be observed this way at all.
/// - `totalUnitCount`, `throughput` and `estimatedTimeRemaining` are all optional in
///   practice. Anything derived from them degrades to "unknown" rather than being guessed.
@MainActor
final class DownloadActivityManager: ObservableObject {
    nonisolated static let shared = DownloadActivityManager()

    /// Everything in flight, plus any download still inside its completion banner window.
    @Published private(set) var items: [DownloadItem] = []

    /// The download whose completion is currently being announced, if any.
    @Published private(set) var completionBanner: DownloadItem?

    /// How often progress reaches the UI. Downloads emit far faster than that, and
    /// re-laying out the notch on every byte is both wasteful and visibly jittery.
    private static let updateInterval: Duration = .milliseconds(250)

    private var subscriberToken: Any?
    private var observations: [URL: [NSKeyValueObservation]] = [:]
    private var progresses: [URL: Progress] = [:]

    /// Updates accumulated since the last flush, keyed by destination URL.
    private var pending: [URL: DownloadSnapshot] = [:]
    private var flushTask: Task<Void, Never>?

    private var bannerTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isRunning = false

    nonisolated private init() {}

    // MARK: - Lifecycle

    func start() {
        // The setting is the master switch; watch it so toggling it takes effect at once
        // rather than at the next launch.
        Defaults.publisher(.enableDownloadListener, options: [])
            .sink { [weak self] _ in Task { @MainActor in self?.applyEnabledState() } }
            .store(in: &cancellables)

        // When a higher-priority activity preempts a download in progress and then expires,
        // the download has to come back. Watching the slot here keeps the coordinator
        // ignorant of downloads. Progress ticks would also re-assert within the update
        // interval, but this covers a stalled download that has stopped emitting.
        BoringViewCoordinator.shared.$expandingView
            .sink { [weak self] item in
                // @Published fires on willSet, so the assignment has not landed yet;
                // re-asserting synchronously here would be re-entrant.
                Task { @MainActor in self?.restoreActivityIfNeeded(after: item) }
            }
            .store(in: &cancellables)

        applyEnabledState()
    }

    func stop() {
        cancellables.removeAll()
        stopObserving()
    }

    private func applyEnabledState() {
        if Defaults[.enableDownloadListener] {
            startObserving()
        } else {
            stopObserving()
        }
    }

    private func startObserving() {
        guard !isRunning else { return }
        // Inside the sandbox `.downloadsDirectory` is the *container's* Downloads, which the
        // downloads entitlement makes a symlink to the real folder. Publishers key their
        // progress on the real path, and the subscription matches URLs literally, so
        // subscribing to the unresolved container path silently never matches anything.
        guard let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first?
            .resolvingSymlinksInPath()
        else {
            NSLog("⬇️ No Downloads folder; download activities unavailable")
            return
        }

        isRunning = true
        NSLog("⬇️ Watching \(downloads.path) for published download progress")

        // Documented to be invoked on the main thread, which is what lets this reach
        // main-actor state directly instead of hopping and losing the non-Sendable Progress.
        subscriberToken = Progress.addSubscriber(forFileURL: downloads) { progress in
            MainActor.assumeIsolated {
                guard let url = DownloadActivityManager.fileURL(of: progress) else { return nil }
                DownloadActivityManager.shared.adopt(progress, url: url)
                // The URL is captured rather than re-read, because the accessors on a proxy
                // are not reliably populated at every point in its life.
                return {
                    MainActor.assumeIsolated {
                        DownloadActivityManager.shared.retire(progress, url: url)
                    }
                }
            }
        }
    }

    private func stopObserving() {
        guard isRunning else { return }
        isRunning = false

        if let subscriberToken {
            Progress.removeSubscriber(subscriberToken)
            self.subscriberToken = nil
        }
        for observation in observations.values.flatMap({ $0 }) {
            observation.invalidate()
        }
        observations.removeAll()
        progresses.removeAll()
        pending.removeAll()
        flushTask?.cancel()
        flushTask = nil
        bannerTask?.cancel()
        bannerTask = nil
        items.removeAll()
        completionBanner = nil
        hideActivity()
    }

    // MARK: - Progress adoption

    /// A freshly vended proxy has its `userInfo` populated but not yet its typed accessors,
    /// so the dictionary is the only reliable source at adoption time. From the first
    /// progress update onward both agree.
    fileprivate static func fileURL(of progress: Progress) -> URL? {
        progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL
    }

    private static func operationKind(of progress: Progress) -> Progress.FileOperationKind? {
        if let kind = progress.fileOperationKind { return kind }
        switch progress.userInfo[.fileOperationKindKey] {
        case let kind as Progress.FileOperationKind: return kind
        case let raw as String: return Progress.FileOperationKind(rawValue: raw)
        default: return nil
        }
    }

    private func adopt(_ progress: Progress, url: URL) {
        let kind = Self.operationKind(of: progress)

        // Logged before filtering: knowing which apps publish, and under what kind, is the
        // only way to tell real coverage from an assumption about it.
        NSLog(
            "⬇️ Published progress: \(url.lastPathComponent) kind=\(kind?.rawValue ?? "nil") "
                + "old=\(progress.isOld) total=\(progress.totalUnitCount) indeterminate=\(progress.isIndeterminate)"
        )

        // A download is what we are after; ordinary Finder copies and duplications into the
        // Downloads folder are not downloads and must not masquerade as them.
        guard let kind, kind == .downloading || kind == .receiving else { return }

        // Level-triggered: subscribing replays downloads already in flight. Adopting them is
        // right, announcing them as freshly started is not.
        guard !progress.isOld else {
            trackSilently(progress, url: url)
            return
        }

        track(progress, url: url)
    }

    private func trackSilently(_ progress: Progress, url: URL) {
        observe(progress, url: url)
        upsert(DownloadSnapshot(progress: progress, url: url).item(startedAt: Date()))
    }

    private func track(_ progress: Progress, url: URL) {
        observe(progress, url: url)
        upsert(DownloadSnapshot(progress: progress, url: url).item(startedAt: Date()))
        showActivity()
    }

    private func observe(_ progress: Progress, url: URL) {
        guard observations[url] == nil else { return }
        progresses[url] = progress

        // KVO fires on whichever thread advanced the progress, so each tick is reduced to a
        // Sendable snapshot before it crosses back to the main actor.
        let handler: @Sendable (Progress, Any) -> Void = { progress, _ in
            let snapshot = DownloadSnapshot(progress: progress, url: url)
            Task { @MainActor in
                DownloadActivityManager.shared.enqueue(snapshot)
            }
        }

        observations[url] = [
            progress.observe(\.fractionCompleted, options: [.new]) { p, c in handler(p, c) },
            progress.observe(\.completedUnitCount, options: [.new]) { p, c in handler(p, c) },
            progress.observe(\.totalUnitCount, options: [.new]) { p, c in handler(p, c) },
            progress.observe(\.isPaused, options: [.new]) { p, c in handler(p, c) },
            progress.observe(\.isCancelled, options: [.new]) { p, c in handler(p, c) },
        ]
    }

    private func retire(_ progress: Progress, url: URL) {
        observations[url]?.forEach { $0.invalidate() }
        observations[url] = nil
        progresses[url] = nil
        pending[url] = nil

        guard let index = items.firstIndex(where: { $0.fileURL == url }) else { return }

        var item = items[index]
        item.state = DownloadActivityState.terminalState(
            isCancelled: progress.isCancelled,
            fraction: progress.fractionCompleted,
            isDeterminate: item.isDeterminate
        )
        items[index] = item

        NSLog("⬇️ Finished: \(item.displayName ?? url.lastPathComponent) → \(item.state)")

        switch item.state {
        case .completed:
            announceCompletion(of: item)
        case .cancelled, .failed:
            // Nothing worth interrupting the user for; drop it and let whatever is still
            // downloading keep the slot.
            items.remove(at: index)
            refreshActivity()
        case .downloading, .paused:
            break
        }
    }

    // MARK: - Throttled updates

    private func enqueue(_ snapshot: DownloadSnapshot) {
        pending[snapshot.url] = snapshot
        guard flushTask == nil else { return }

        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.updateInterval)
            guard let self, !Task.isCancelled else { return }
            self.flushTask = nil
            self.flush()
        }
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        let snapshots = pending
        pending.removeAll()

        for snapshot in snapshots.values {
            guard let index = items.firstIndex(where: { $0.fileURL == snapshot.url }) else { continue }
            items[index] = snapshot.item(startedAt: items[index].startedAt)
        }
        refreshActivity()
    }

    private func upsert(_ item: DownloadItem) {
        if let index = items.firstIndex(where: { $0.fileURL == item.fileURL }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    // MARK: - Activity routing

    /// Downloads still in flight, i.e. what the activity actually represents.
    var activeDownloads: [DownloadItem] { items.filter { !$0.state.isTerminal } }

    var summary: DownloadSummary? { DownloadActivityState.summarize(items) }

    /// True while the notch should be showing something about downloads, which is also what
    /// gates the expanded Downloads tab.
    var hasVisibleActivity: Bool { !activeDownloads.isEmpty || completionBanner != nil }

    private func showActivity() {
        BoringViewCoordinator.shared.toggleExpandingView(
            status: true,
            type: .download,
            // Off means the user wants a blip at each end rather than a persistent readout,
            // so the ordinary auto-dismiss timer applies instead.
            sticky: Defaults[.downloadStickyActivity]
        )
    }

    private func hideActivity() {
        let coordinator = BoringViewCoordinator.shared

        // The Downloads tab goes away with the downloads, so anyone left looking at it has
        // to be moved off it — the same thing the coordinator does when the shelf is
        // switched off underneath it.
        if coordinator.currentView == .downloads {
            coordinator.currentView = .home
        }

        guard coordinator.expandingView.show, coordinator.expandingView.type == .download else { return }
        coordinator.toggleExpandingView(status: false, type: .download)
    }

    private func refreshActivity() {
        if activeDownloads.isEmpty, completionBanner == nil {
            hideActivity()
        } else if completionBanner == nil {
            showActivity()
        }
    }

    private func announceCompletion(of item: DownloadItem) {
        items.removeAll { $0.fileURL == item.fileURL }
        completionBanner = item

        // Chromium never publishes the real name, but at completion it has just renamed the
        // partial file to it. Recovering it costs one directory read, once, and only for a
        // download that finished without ever revealing its name.
        if item.displayName == nil, let total = item.totalBytes, total > 0 {
            let directory = item.fileURL.deletingLastPathComponent()
            Task { [weak self] in
                let resolved = await Self.resolveCompletedName(size: total, in: directory)
                guard let self, let resolved else { return }
                NSLog("⬇️ Resolved final name: \(resolved)")
                await MainActor.run {
                    guard self.completionBanner?.fileURL == item.fileURL else { return }
                    self.completionBanner?.displayName = resolved
                }
            }
        }

        // Not sticky: the coordinator's own timer takes the banner down, and because the
        // notch's base content is derived live rather than stored, Now Playing comes back
        // on its own afterwards.
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .download)

        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.completionBanner = nil
            // Anything still downloading reclaims the slot; otherwise this is a no-op
            // because the coordinator has already dismissed the banner.
            self.refreshActivity()
        }
    }

    /// Find the file a just-finished download turned into, by exact size.
    ///
    /// Deliberately strict: an exact byte-count match, written within the last few seconds,
    /// and *unique*. Two candidates of identical size mean we cannot tell which is which, so
    /// it reports nothing rather than labelling the download with the wrong name.
    nonisolated private static func resolveCompletedName(size: Int64, in directory: URL) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            ) else { return nil }

            let cutoff = Date().addingTimeInterval(-10)
            let matches = entries.filter { url in
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      Int64(values.fileSize ?? -1) == size,
                      let modified = values.contentModificationDate, modified >= cutoff
                else { return false }
                return !DownloadNaming.isInProgressArtefact(url.lastPathComponent)
            }

            guard matches.count == 1 else { return nil }
            return matches[0].lastPathComponent
        }.value
    }

    /// Put a sticky download activity back after something more important displaced it.
    private func restoreActivityIfNeeded(after item: ExpandedItem) {
        guard Defaults[.enableDownloadListener], Defaults[.downloadStickyActivity] else { return }
        guard !activeDownloads.isEmpty, completionBanner == nil else { return }
        // Only step in once the slot is actually free. Re-asserting sets `show` back to
        // true, so this guard is also what stops the sink from feeding itself.
        guard !BoringViewCoordinator.shared.expandingView.show else { return }
        _ = item
        showActivity()
    }
}

/// A thread-safe reading of a `Progress`, taken so that KVO ticks arriving on arbitrary
/// threads can cross to the main actor as plain values.
private struct DownloadSnapshot: Sendable {
    let url: URL
    let displayName: String?
    let fraction: Double
    let completedBytes: Int64
    let totalBytes: Int64?
    let throughput: Int?
    let eta: TimeInterval?
    let isPaused: Bool
    let isCancelled: Bool

    init(progress: Progress, url: URL) {
        self.url = url
        // Downloaders publish against the partial file, so the raw name is usually an
        // implementation detail rather than something worth showing.
        self.displayName = DownloadNaming.displayName(forPublished: url.lastPathComponent)
        self.fraction = progress.fractionCompleted
        self.completedBytes = progress.completedUnitCount
        // `isIndeterminate` and a non-positive total both mean "size unknown"; either way a
        // percentage would be fabricated.
        self.totalBytes = (progress.isIndeterminate || progress.totalUnitCount <= 0)
            ? nil : progress.totalUnitCount
        self.throughput = progress.throughput
        self.eta = progress.estimatedTimeRemaining
        self.isPaused = progress.isPaused
        self.isCancelled = progress.isCancelled
    }

    func item(startedAt: Date) -> DownloadItem {
        DownloadItem(
            fileURL: url,
            displayName: displayName,
            fraction: fraction,
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            throughput: throughput,
            eta: eta,
            state: isPaused ? .paused : .downloading,
            startedAt: startedAt
        )
    }
}
