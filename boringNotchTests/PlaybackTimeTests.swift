import XCTest
@testable import boringNotch

final class PlaybackTimeTests: XCTestCase {
    func testInvalidValuesHaveNoSeekRangeOrDisplayConversion() {
        for value in [Double.nan, .infinity, -.infinity, -5, 1e20, Double(Int64.max)] {
            XCTAssertNil(PlaybackTime.seekRange(duration: value))
            XCTAssertEqual(PlaybackTime.string(from: value), "--:--")
            XCTAssertEqual(PlaybackTime.sanitized(value), 0)
        }
    }

    func testRelativeSeekUsesEstimatedPositionInsteadOfStaleSample() {
        XCTAssertEqual(PlaybackTime.relativeSeekTarget(seconds: 15, elapsed: 10, duration: 200,
            rate: 1, playing: true, sampledAt: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 120)), 45)
        XCTAssertNil(PlaybackTime.relativeSeekTarget(seconds: 15, elapsed: 10, duration: 0,
            rate: 1, playing: true, sampledAt: Date(), now: Date()))
    }

    func testUnknownDurationIsNotASeekRange() {
        XCTAssertNil(PlaybackTime.seekRange(duration: 0))
        XCTAssertEqual(PlaybackTime.position(elapsed: 40, duration: 0, rate: 1,
            playing: true, sampledAt: Date(timeIntervalSince1970: 10), now: Date(timeIntervalSince1970: 20)), 50)
    }

    func testHoursAndLargeFiniteDurationsAreNotTruncatedTo32Bits() {
        XCTAssertEqual(PlaybackTime.string(from: 3_661), "1:01:01")
        XCTAssertEqual(PlaybackTime.string(from: 360_001), "100:00:01")
        XCTAssertEqual(PlaybackTime.string(from: 8_000_000_000_000), "2222222222:13:20")
        XCTAssertNotNil(PlaybackTime.seekRange(duration: 360_001))
        XCTAssertNotNil(PlaybackTime.seekRange(duration: PlaybackTime.maximumSeconds))
    }

    func testPositionUsesCurrentClockAndClampsAtDuration() {
        let sample = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(PlaybackTime.position(elapsed: 10, duration: 90, rate: 2,
            playing: true, sampledAt: sample, now: sample.addingTimeInterval(20)), 50)
        XCTAssertEqual(PlaybackTime.position(elapsed: 10, duration: 90, rate: 2,
            playing: false, sampledAt: sample, now: sample.addingTimeInterval(20)), 10)
        XCTAssertEqual(PlaybackTime.position(elapsed: 80, duration: 90, rate: 2,
            playing: true, sampledAt: sample, now: sample.addingTimeInterval(20)), 90)
    }
}
