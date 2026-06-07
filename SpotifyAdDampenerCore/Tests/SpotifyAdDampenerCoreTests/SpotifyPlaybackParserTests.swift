import XCTest
@testable import SpotifyAdDampenerCore

final class SpotifyPlaybackParserTests: XCTestCase {
    func testParsesAdPlayback() throws {
        let snapshot = try SpotifyPlaybackParser.parse(statusCode: 200, data: data(type: "ad", isPlaying: true, progressMs: 1234, durationMs: 30000))
        XCTAssertEqual(snapshot, SpotifyPlaybackSnapshot(kind: .ad, isPlaying: true, progressMs: 1234, durationMs: 30000))
    }

    func testParsesTrackPlayback() throws {
        let snapshot = try SpotifyPlaybackParser.parse(statusCode: 200, data: data(type: "track", isPlaying: true, progressMs: 55, durationMs: 180000))
        XCTAssertEqual(snapshot.kind, .track)
        XCTAssertEqual(snapshot.isPlaying, true)
        XCTAssertEqual(snapshot.progressMs, 55)
        XCTAssertEqual(snapshot.durationMs, 180000)
    }

    func testParsesEpisodePlayback() throws {
        let snapshot = try SpotifyPlaybackParser.parse(statusCode: 200, data: data(type: "episode", isPlaying: false, progressMs: nil, durationMs: 2700000))
        XCTAssertEqual(snapshot.kind, .episode)
        XCTAssertEqual(snapshot.isPlaying, false)
        XCTAssertNil(snapshot.progressMs)
        XCTAssertEqual(snapshot.durationMs, 2700000)
    }

    func testUnknownAndMissingTypesParseAsUnknown() throws {
        let unknown = try SpotifyPlaybackParser.parse(statusCode: 200, data: data(type: "audiobook", isPlaying: true, progressMs: nil, durationMs: nil))
        XCTAssertEqual(unknown.kind, .unknown("audiobook"))

        let missing = try SpotifyPlaybackParser.parse(statusCode: 200, data: #"{"is_playing":true}"#.data(using: .utf8))
        XCTAssertEqual(missing.kind, .unknown(nil))
    }

    func testNoContentOrNoBodyParsesAsNotPlaying() throws {
        XCTAssertEqual(try SpotifyPlaybackParser.parse(statusCode: 204, data: nil).kind, .notPlaying)
        XCTAssertEqual(try SpotifyPlaybackParser.parse(statusCode: 200, data: Data()).kind, .notPlaying)
    }

    private func data(type: String, isPlaying: Bool, progressMs: Int?, durationMs: Int?) -> Data {
        var json: [String: Any] = [
            "currently_playing_type": type,
            "is_playing": isPlaying
        ]
        if let progressMs { json["progress_ms"] = progressMs }
        if let durationMs { json["item"] = ["duration_ms": durationMs] }
        return try! JSONSerialization.data(withJSONObject: json)
    }
}
