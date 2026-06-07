import Combine
import Defaults
import Foundation
import SpotifyAdDampenerCore

@MainActor
final class SpotifyAdDampenerManager: ObservableObject {
    static let shared = SpotifyAdDampenerManager()

    @Published private(set) var authService: SpotifyAuthService
    @Published private(set) var isDampened = false
    @Published private(set) var statusText = "Off"
    @Published private(set) var lastErrorText: String?

    private let volumeManager: VolumeManager
    private let callGuard: CallGuardService
    private var monitor: SpotifyAdMonitor!
    private var stateMachine: AdDampenerStateMachine
    private var cancellables: Set<AnyCancellable> = []
    private var ownedSessionID: UUID?
    private var lastCommandedVolume: Float?

    private init() {
        let authService = SpotifyAuthService()
        let volumeManager = VolumeManager.shared
        let callGuard = CallGuardService.shared
        self.authService = authService
        self.volumeManager = volumeManager
        self.callGuard = callGuard
        self.stateMachine = AdDampenerStateMachine(
            settingsEnabled: Defaults[.spotifyAdDampenerEnabled],
            targetVolume: Float(Defaults[.spotifyAdDampenerTargetVolume])
        )
        self.monitor = SpotifyAdMonitor(api: SpotifyPlaybackAPI(authService: authService))
        self.monitor.onResult = { [weak self] result in self?.handlePlaybackResult(result) }
        setupObservers()
        restoreStaleOwnedSessionIfNeeded()
        startIfNeeded()
    }

    var canConnect: Bool { authService.isConfigured }
    var authStateText: String {
        switch authService.state {
        case .notConfigured: return "Spotify Client ID missing"
        case .signedOut: return "Not connected"
        case .authorizing: return "Waiting for Spotify authorization"
        case .signedIn: return "Connected"
        case .error(let message): return message
        }
    }

    func startIfNeeded() {
        callGuard.start()
        guard Defaults[.spotifyAdDampenerEnabled] else {
            monitor.stop()
            statusText = "Off"
            return
        }
        guard case .signedIn = authService.state else {
            monitor.stop()
            statusText = authStateText
            return
        }
        statusText = "Monitoring Spotify"
        monitor.start()
    }

    func stopAndRestore() {
        monitor.stop()
        execute(commands: stateMachine.handle(.settingsEnabled(false)))
        if let sessionID = ownedSessionID, let saved = Defaults[.spotifyAdDampenerOwnedSavedVolume] {
            volumeManager.spotifyAdDampenerSetVolume(Float(saved))
            clearOwnedSession()
            lastCommandedVolume = nil
            isDampened = false
            statusText = "Off"
            _ = sessionID
        }
    }

    func connect() { authService.connect() }
    func disconnect() {
        stopAndRestore()
        authService.disconnect()
        startIfNeeded()
    }
    func handleCallbackURL(_ url: URL) { authService.handleCallbackURL(url) }
    func refreshNow() { monitor.refreshNow() }

    private func setupObservers() {
        Defaults.publisher(.spotifyAdDampenerEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self else { return }
                let enabled = change.newValue
                self.execute(commands: self.stateMachine.handle(.settingsEnabled(enabled)))
                enabled ? self.startIfNeeded() : self.stopAndRestore()
            }
            .store(in: &cancellables)

        Defaults.publisher(.spotifyAdDampenerManualCallSuppress)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.callGuard.evaluate() }
            .store(in: &cancellables)

        Defaults.publisher(.spotifyAdDampenerTargetVolume)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self else { return }
                self.execute(commands: self.stateMachine.handle(.targetVolumeChanged(Float(change.newValue))))
            }
            .store(in: &cancellables)

        volumeManager.$rawVolume
            .receive(on: RunLoop.main)
            .sink { [weak self] volume in
                guard let self else { return }
                let value = Float(volume)
                self.execute(commands: self.stateMachine.handle(.currentSystemVolume(value)))
                if let commanded = self.lastCommandedVolume, abs(value - commanded) > 0.04 {
                    self.execute(commands: self.stateMachine.handle(.manualVolumeChanged(value)))
                    self.lastCommandedVolume = nil
                    self.isDampened = false
                    self.statusText = "User changed volume; dampening released"
                }
            }
            .store(in: &cancellables)

        callGuard.$isCallLikelyActive
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                guard let self else { return }
                self.execute(commands: self.stateMachine.handle(.callActive(active)))
                if active { self.statusText = self.callGuard.statusText }
            }
            .store(in: &cancellables)

        authService.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.startIfNeeded() }
            .store(in: &cancellables)
    }

    private func handlePlaybackResult(_ result: SpotifyPlaybackAPI.PlaybackResult) {
        switch result {
        case .snapshot(let snapshot):
            execute(commands: stateMachine.handle(.spotifyPlayback(snapshot)))
            if case .ad = snapshot.kind {
                statusText = isDampened ? "Dampening Spotify ad" : "Ad detected, suppressed"
            } else if !isDampened {
                statusText = "Monitoring Spotify"
            }
            lastErrorText = nil
        case .authRequired:
            execute(commands: stateMachine.handle(.authFailed))
            statusText = "Spotify authorization required"
        case .networkFailed:
            execute(commands: stateMachine.handle(.networkFailed))
            statusText = "Spotify API unavailable; volume restored"
            lastErrorText = "Network or parsing error"
        }
    }

    private func execute(commands: [AdDampenerCommand]) {
        for command in commands {
            switch command {
            case .lowerVolume(let target, _, let sessionID):
                guard !callGuard.isCallLikelyActive else { continue }
                ownedSessionID = sessionID
                lastCommandedVolume = target
                volumeManager.spotifyAdDampenerSetVolume(target)
                isDampened = true
            case .restoreVolume(let saved, let sessionID):
                guard ownedSessionID == nil || ownedSessionID == sessionID else { continue }
                lastCommandedVolume = saved
                volumeManager.spotifyAdDampenerSetVolume(saved)
                isDampened = false
            case .persistOwnedSession(let session):
                persist(session)
            case .clearOwnedSession:
                clearOwnedSession()
            case .showIndicator(let message):
                statusText = message
            case .none:
                break
            }
        }
    }

    private func persist(_ session: DampeningSession) {
        ownedSessionID = session.id
        Defaults[.spotifyAdDampenerOwnedSessionID] = session.id.uuidString
        Defaults[.spotifyAdDampenerOwnedSavedVolume] = Double(session.savedVolume)
        Defaults[.spotifyAdDampenerOwnedStartedAt] = session.startedAt
    }

    private func clearOwnedSession() {
        ownedSessionID = nil
        Defaults[.spotifyAdDampenerOwnedSessionID] = nil
        Defaults[.spotifyAdDampenerOwnedSavedVolume] = nil
        Defaults[.spotifyAdDampenerOwnedStartedAt] = nil
    }

    private func restoreStaleOwnedSessionIfNeeded() {
        guard let idString = Defaults[.spotifyAdDampenerOwnedSessionID],
              let id = UUID(uuidString: idString),
              let saved = Defaults[.spotifyAdDampenerOwnedSavedVolume] else { return }
        let session = DampeningSession(id: id, savedVolume: Float(saved), targetVolume: Float(Defaults[.spotifyAdDampenerTargetVolume]), startedAt: Defaults[.spotifyAdDampenerOwnedStartedAt] ?? Date())
        ownedSessionID = id
        execute(commands: stateMachine.handle(.appLaunchedWithOwnedSession(session)))
        statusText = "Restored stale dampened volume"
    }
}
