import Foundation

public enum AdDampenerState: Equatable {
    case disabled
    case idle
    case monitoring
    case dampened(DampeningSession)
    case suppressedByCall
    case authRequired
    case errorRecoverable(String)
}

public struct DampeningSession: Equatable {
    public let id: UUID
    public let savedVolume: Float
    public let targetVolume: Float
    public let startedAt: Date

    public init(id: UUID, savedVolume: Float, targetVolume: Float, startedAt: Date) {
        self.id = id
        self.savedVolume = savedVolume
        self.targetVolume = targetVolume
        self.startedAt = startedAt
    }
}

public enum AdDampenerEvent: Equatable {
    case settingsEnabled(Bool)
    case targetVolumeChanged(Float)
    case spotifyPlayback(SpotifyPlaybackSnapshot)
    case callActive(Bool)
    case currentSystemVolume(Float)
    case manualVolumeChanged(Float)
    case authFailed
    case networkFailed
    case appLaunchedWithOwnedSession(DampeningSession)
}

public enum AdDampenerCommand: Equatable {
    case lowerVolume(to: Float, save: Float, sessionID: UUID)
    case restoreVolume(to: Float, sessionID: UUID)
    case persistOwnedSession(DampeningSession)
    case clearOwnedSession
    case showIndicator(String)
    case none
}

public struct AdDampenerStateMachine {
    public private(set) var state: AdDampenerState
    public private(set) var callIsActive: Bool
    public private(set) var currentVolume: Float
    public private(set) var targetVolume: Float

    private let now: () -> Date
    private let uuid: () -> UUID
    private var restoredLaunchSessionIDs: Set<UUID> = []

    public init(
        settingsEnabled: Bool,
        targetVolume: Float,
        initialState: AdDampenerState? = nil,
        now: @escaping () -> Date = Date.init,
        uuid: @escaping () -> UUID = UUID.init
    ) {
        self.state = initialState ?? (settingsEnabled ? .idle : .disabled)
        self.callIsActive = false
        self.currentVolume = 1.0
        self.targetVolume = targetVolume
        self.now = now
        self.uuid = uuid
    }

    public mutating func handle(_ event: AdDampenerEvent) -> [AdDampenerCommand] {
        switch event {
        case .settingsEnabled(let enabled):
            state = enabled ? .idle : .disabled
            return []
        case .targetVolumeChanged(let volume):
            targetVolume = min(max(volume, 0), 1)
            return []
        case .currentSystemVolume(let volume):
            currentVolume = volume
            return []
        case .callActive(let active):
            callIsActive = active
            if active, case .dampened(let session) = state {
                state = .suppressedByCall
                return [.restoreVolume(to: session.savedVolume, sessionID: session.id), .clearOwnedSession]
            }
            if !active, state == .suppressedByCall { state = .idle }
            return []
        case .spotifyPlayback(let snapshot):
            return handlePlayback(snapshot)
        case .authFailed:
            if case .dampened(let session) = state {
                state = .idle
                return [.restoreVolume(to: session.savedVolume, sessionID: session.id), .clearOwnedSession]
            }
            state = .authRequired
            return []
        case .networkFailed:
            if case .dampened(let session) = state {
                state = .idle
                return [.restoreVolume(to: session.savedVolume, sessionID: session.id), .clearOwnedSession]
            }
            state = .errorRecoverable("networkFailed")
            return []
        case .manualVolumeChanged:
            if case .dampened = state {
                state = .idle
                return [.clearOwnedSession]
            }
            return []
        case .appLaunchedWithOwnedSession(let session):
            guard !restoredLaunchSessionIDs.contains(session.id) else { return [] }
            restoredLaunchSessionIDs.insert(session.id)
            state = .idle
            return [.restoreVolume(to: session.savedVolume, sessionID: session.id), .clearOwnedSession]
        }
    }

    private mutating func handlePlayback(_ snapshot: SpotifyPlaybackSnapshot) -> [AdDampenerCommand] {
        guard state != .disabled else { return [] }

        if case .ad = snapshot.kind {
            if callIsActive {
                state = .suppressedByCall
                return []
            }
            switch state {
            case .idle, .monitoring, .suppressedByCall, .authRequired, .errorRecoverable:
                let session = DampeningSession(id: uuid(), savedVolume: currentVolume, targetVolume: targetVolume, startedAt: now())
                state = .dampened(session)
                return [.lowerVolume(to: targetVolume, save: currentVolume, sessionID: session.id), .persistOwnedSession(session)]
            case .dampened, .disabled:
                return []
            }
        }

        if case .dampened(let session) = state {
            state = .idle
            return [.restoreVolume(to: session.savedVolume, sessionID: session.id), .clearOwnedSession]
        }
        return []
    }
}
