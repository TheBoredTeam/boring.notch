import Foundation

@MainActor
final class SpotifyAdMonitor {
    var onResult: ((SpotifyPlaybackAPI.PlaybackResult) -> Void)?

    private let api: SpotifyPlaybackAPI
    private var timer: Timer?
    private var notificationObserver: Any?
    private var pollTask: Task<Void, Never>?

    init(api: SpotifyPlaybackAPI) {
        self.api = api
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        refreshNow()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let notificationObserver {
            DistributedNotificationCenter.default().removeObserver(notificationObserver)
            self.notificationObserver = nil
        }
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshNow() {
        pollTask?.cancel()
        pollTask = Task { [api, weak self] in
            let result = await api.currentlyPlaying()
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.onResult?(result) }
        }
    }
}
