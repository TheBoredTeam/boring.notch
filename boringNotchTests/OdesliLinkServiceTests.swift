//
//  OdesliLinkServiceTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class OdesliLinkServiceTests: XCTestCase {

    // Fixtures: the real iTunes Search result for "Thriller" / Michael Jackson.
    //   album id 269572838, track id 269573303
    private static let thrillerTrackURL = URL(string: "https://music.apple.com/us/album/thriller/269572838?i=269573303&uo=4")!
    private static let thrillerAlbumURL = URL(string: "https://music.apple.com/us/album/thriller/269572838")!

    // MARK: - song.link page URL construction

    func testTrackUrlUsesTrackIdFromQuery() throws {
        let page = try OdesliLinkService.songLinkPageUrl(kind: .track, appleMusicUrl: Self.thrillerTrackURL)
        XCTAssertEqual(page.absoluteString, "https://song.link/i/269573303")
    }

    func testAlbumUrlUsesAlbumIdFromPath() throws {
        let page = try OdesliLinkService.songLinkPageUrl(kind: .album, appleMusicUrl: Self.thrillerAlbumURL)
        XCTAssertEqual(page.absoluteString, "https://album.link/i/269572838")
    }

    func testAlbumUrlIgnoresTrailingQuery() throws {
        let apple = URL(string: "https://music.apple.com/gb/album/thriller/269572838?uo=4")!
        let page = try OdesliLinkService.songLinkPageUrl(kind: .album, appleMusicUrl: apple)
        XCTAssertEqual(page.absoluteString, "https://album.link/i/269572838")
    }

    func testAlbumFromTrackUrlPrefersAlbumIdNotTrackId() throws {
        // The .album path strips the ?i= query before we see the URL, but be
        // explicit that path id wins even if a stray i= is present.
        let page = try OdesliLinkService.songLinkPageUrl(kind: .album, appleMusicUrl: Self.thrillerTrackURL)
        XCTAssertEqual(page.absoluteString, "https://album.link/i/269572838")
    }

    func testTrackWithoutTrackIdThrowsNotFound() {
        XCTAssertThrowsError(try OdesliLinkService.songLinkPageUrl(kind: .track, appleMusicUrl: Self.thrillerAlbumURL)) {
            XCTAssertEqual($0 as? ShareLinkError, .notFound)
        }
    }

    func testEmptyTrackIdThrowsNotFound() {
        let apple = URL(string: "https://music.apple.com/us/album/thriller/269572838?i=")!
        XCTAssertThrowsError(try OdesliLinkService.songLinkPageUrl(kind: .track, appleMusicUrl: apple)) {
            XCTAssertEqual($0 as? ShareLinkError, .notFound)
        }
    }

    func testNonNumericTrackIdThrowsNotFound() {
        let apple = URL(string: "https://music.apple.com/us/album/thriller/269572838?i=abc123")!
        XCTAssertThrowsError(try OdesliLinkService.songLinkPageUrl(kind: .track, appleMusicUrl: apple)) {
            XCTAssertEqual($0 as? ShareLinkError, .notFound)
        }
    }

    func testNonAppleMusicHostThrowsNotFound() {
        let other = URL(string: "https://example.com/us/album/x/123?i=456")!
        XCTAssertThrowsError(try OdesliLinkService.songLinkPageUrl(kind: .track, appleMusicUrl: other)) {
            XCTAssertEqual($0 as? ShareLinkError, .notFound)
        }
    }
}

/// End-to-end canary against the *live* iTunes Search API and the song.link
/// front end. Skipped by default so the normal/CI test run stays hermetic.
///
/// To run it:
///   - Xcode: add `ODESLI_LIVE_TEST = 1` to the test action's environment.
///   - CLI:   `TEST_RUNNER_ODESLI_LIVE_TEST=1 xcodebuild ... test`
///            (xcodebuild only forwards env vars to the test runner when they
///             carry the `TEST_RUNNER_` prefix, which it then strips.)
///
/// This is the test that would have caught the Odesli public-API shutdown: the
/// offline tests above only prove our URL math, not that the upstream contracts
/// still hold.
final class OdesliLinkServiceLiveTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ODESLI_LIVE_TEST"] == "1",
            "Set ODESLI_LIVE_TEST=1 to run the network canary test"
        )
    }

    func testResolvesThrillerTrackEndToEnd() async throws {
        let service = OdesliLinkService()
        let result = try await service.resolveShareLink(
            kind: .track, title: "Thriller", artist: "Michael Jackson", album: "Thriller"
        )

        XCTAssertEqual(result.pageUrl.host, "song.link")
        XCTAssertTrue(
            result.pageUrl.path.hasPrefix("/i/"),
            "expected a song.link/i/<id> URL, got \(result.pageUrl.absoluteString)"
        )

        // The song.link front end must still resolve that bare Apple id.
        var request = URLRequest(url: result.pageUrl)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
}
