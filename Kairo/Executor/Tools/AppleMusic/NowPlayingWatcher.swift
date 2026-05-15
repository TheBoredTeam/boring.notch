import Foundation

@MainActor
final class NowPlayingWatcher {
    static let shared = NowPlayingWatcher()

    private var timer: Timer?
    private var lastTrack: String?
    private var isShowing = false

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() async {
        let current = await AppleMusicService.currentTrack()

        guard let track = current, track.isPlaying else {
            if isShowing {
                KairoRuntime.shared.dismiss()
                isShowing = false
                lastTrack = nil
            }
            return
        }

        let key = "\(track.title)|\(track.artist)"
        if key != lastTrack {
            lastTrack = key
            KairoRuntime.shared.present(.nowPlaying, payload: track)
            isShowing = true
        }
    }
}
