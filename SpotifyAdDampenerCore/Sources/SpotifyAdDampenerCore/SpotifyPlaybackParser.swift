import Foundation

public enum SpotifyPlaybackParser {
    private struct Response: Decodable {
        let currentlyPlayingType: String?
        let isPlaying: Bool?
        let progressMs: Int?
        let item: Item?

        enum CodingKeys: String, CodingKey {
            case currentlyPlayingType = "currently_playing_type"
            case isPlaying = "is_playing"
            case progressMs = "progress_ms"
            case item
        }
    }

    private struct Item: Decodable {
        let durationMs: Int?

        enum CodingKeys: String, CodingKey {
            case durationMs = "duration_ms"
        }
    }

    public static func parse(statusCode: Int, data: Data?) throws -> SpotifyPlaybackSnapshot {
        guard statusCode != 204, let data, !data.isEmpty else {
            return SpotifyPlaybackSnapshot(kind: .notPlaying, isPlaying: false, progressMs: nil, durationMs: nil)
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        let kind: SpotifyPlaybackKind
        switch response.currentlyPlayingType {
        case "ad": kind = .ad
        case "track": kind = .track
        case "episode": kind = .episode
        case let value: kind = .unknown(value)
        }

        return SpotifyPlaybackSnapshot(
            kind: kind,
            isPlaying: response.isPlaying ?? false,
            progressMs: response.progressMs,
            durationMs: response.item?.durationMs
        )
    }
}
