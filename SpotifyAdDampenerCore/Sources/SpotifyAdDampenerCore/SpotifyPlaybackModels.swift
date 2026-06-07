import Foundation

public enum SpotifyPlaybackKind: Equatable {
    case ad
    case track
    case episode
    case notPlaying
    case unknown(String?)
}

public struct SpotifyPlaybackSnapshot: Equatable {
    public let kind: SpotifyPlaybackKind
    public let isPlaying: Bool
    public let progressMs: Int?
    public let durationMs: Int?

    public init(kind: SpotifyPlaybackKind, isPlaying: Bool, progressMs: Int?, durationMs: Int?) {
        self.kind = kind
        self.isPlaying = isPlaying
        self.progressMs = progressMs
        self.durationMs = durationMs
    }
}
