//
//  LastFMScrobblePolicyTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class LastFMScrobblePolicyTests: XCTestCase {

    func testDoesNotScrobbleTracksShorterThan30Seconds() {
        XCTAssertFalse(LastFMScrobblePolicy.shouldScrobble(duration: 29, elapsed: 29))
        XCTAssertFalse(LastFMScrobblePolicy.shouldScrobble(duration: 15, elapsed: 15))
    }

    func testScrobblesAtHalfDurationForShortTracks() {
        XCTAssertFalse(LastFMScrobblePolicy.shouldScrobble(duration: 120, elapsed: 59))
        XCTAssertTrue(LastFMScrobblePolicy.shouldScrobble(duration: 120, elapsed: 60))
    }

    func testCapsThresholdAtFourMinutes() {
        // 10-minute track → threshold is 240s, not 300s
        XCTAssertFalse(LastFMScrobblePolicy.shouldScrobble(duration: 600, elapsed: 239))
        XCTAssertTrue(LastFMScrobblePolicy.shouldScrobble(duration: 600, elapsed: 240))
    }

    func testExactlyThirtySecondsUsesHalfDuration() {
        XCTAssertFalse(LastFMScrobblePolicy.shouldScrobble(duration: 30, elapsed: 14))
        XCTAssertTrue(LastFMScrobblePolicy.shouldScrobble(duration: 30, elapsed: 15))
    }

    func testMD5MatchesKnownVector() {
        // RFC 1321 test vector
        XCTAssertEqual("".md5, "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual("abc".md5, "900150983cd24fb0d6963f7d28e17f72")
    }
}
