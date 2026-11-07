import XCTest
@testable import boringNotch

@MainActor
final class LyricsServiceTests: XCTestCase {
    func testParseLRCParsesTimestampPrecisionAndKeepsChronologicalOrder() {
        let parsed = LyricsService.shared.parseLRC(
            """
            [00:02.250]Second
            [00:01.5]First
            [00:03.25]Third
            """
        )

        XCTAssertEqual(parsed.map(\.text), ["First", "Second", "Third"])
        XCTAssertEqual(parsed[0].time, 1.5, accuracy: 0.001)
        XCTAssertEqual(parsed[1].time, 2.25, accuracy: 0.001)
        XCTAssertEqual(parsed[2].time, 3.25, accuracy: 0.001)
    }

    func testActiveLyricIndexBeforeAtAndBetweenTimestamps() {
        let lyrics: [(time: Double, text: String)] = [
            (10, "First line"),
            (20, "Second line"),
            (30, "Third line")
        ]

        XCTAssertNil(LyricsService.activeLyricIndex(in: lyrics, at: 9.99))
        XCTAssertEqual(LyricsService.activeLyricIndex(in: lyrics, at: 10), 0)
        XCTAssertEqual(LyricsService.activeLyricIndex(in: lyrics, at: 19.99), 0)
        XCTAssertEqual(LyricsService.activeLyricIndex(in: lyrics, at: 20), 1)
        XCTAssertEqual(LyricsService.activeLyricIndex(in: lyrics, at: 29.99), 1)
        XCTAssertEqual(LyricsService.activeLyricIndex(in: lyrics, at: 30), 2)
        XCTAssertEqual(LyricsService.activeLyricIndex(in: lyrics, at: 45), 2)
    }
}
