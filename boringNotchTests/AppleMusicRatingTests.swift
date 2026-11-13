import AppKit
import XCTest

@testable import boringNotch

final class AppleMusicRatingTests: XCTestCase {
    func testRatingUsesMusicScaleAndSupportsRemovingRating() throws {
        for stars in 0...5 {
            let rating = try XCTUnwrap(MusicTrackRating(trackID: "0123456789ABCDEF", value: stars * 20))
            XCTAssertEqual(rating.stars, stars)
        }
    }

    func testInvalidRatingsAndTrackIDsAreRejected() {
        for value in [-1, 101] {
            XCTAssertNil(MusicTrackRating(trackID: "0123456789ABCDEF", value: value))
        }
        for trackID in ["", "not-a-track", "\"\nquit", "１２３４"] {
            XCTAssertNil(MusicTrackRating(trackID: trackID, value: 60))
        }
    }

    func testPlaybackUpdatesIncludeRatingOnlyChanges() throws {
        var original = PlaybackState(bundleIdentifier: "com.apple.Music")
        original.trackRating = try XCTUnwrap(MusicTrackRating(trackID: "0123456789ABCDEF", value: 20))
        var updated = original
        updated.trackRating = try XCTUnwrap(MusicTrackRating(trackID: "0123456789ABCDEF", value: 80))
        XCTAssertNotEqual(original, updated)
        updated.trackRating = nil
        XCTAssertNotEqual(original, updated)
    }

    func testPlaybackDescriptorDecodesRatingAndClearsUnavailableTracks() throws {
        let descriptor = NSAppleEventDescriptor.list()
        for index in 1...11 {
            descriptor.insert(NSAppleEventDescriptor(boolean: false), at: index)
        }
        XCTAssertNil(AppleMusicRatingAccess.rating(from: descriptor))
        descriptor.insert(NSAppleEventDescriptor(string: "0123456789ABCDEF"), at: 12)
        descriptor.insert(NSAppleEventDescriptor(int32: 80), at: 13)
        XCTAssertEqual(AppleMusicRatingAccess.rating(from: descriptor)?.stars, 4)
        descriptor.remove(at: 13)
        descriptor.insert(NSAppleEventDescriptor(int32: -1), at: 13)
        XCTAssertNil(AppleMusicRatingAccess.rating(from: descriptor))
        descriptor.remove(at: 13)
        descriptor.insert(NSAppleEventDescriptor(string: "unavailable"), at: 13)
        XCTAssertNil(AppleMusicRatingAccess.rating(from: descriptor))
    }

    func testRatingCommandTargetsLibraryTrackAndCompiles() async throws {
        let rating = try XCTUnwrap(MusicTrackRating(trackID: "0123456789ABCDEF", value: 80))
        try await AppleMusicRatingAccess.setRating(rating) { source in
            XCTAssertTrue(source.contains("if application \"Music\" is not running then return false"))
            XCTAssertTrue(source.contains("if persistent ID of current track is not \"0123456789ABCDEF\" then return false"))
            XCTAssertTrue(source.contains("first track of library playlist 1 whose persistent ID is \"0123456789ABCDEF\""))
            XCTAssertTrue(source.contains("set rating of targetTrack to 80"))
            let script = try XCTUnwrap(NSAppleScript(source: source))
            var error: NSDictionary?
            XCTAssertTrue(script.compileAndReturnError(&error), "\(String(describing: error))")
            return NSAppleEventDescriptor(boolean: true)
        }
    }

    func testTrackChangeOrMissingResponseDoesNotReportSuccess() async throws {
        let rating = try XCTUnwrap(MusicTrackRating(trackID: "0123456789ABCDEF", value: 0))
        for response in [NSAppleEventDescriptor(boolean: false), nil] {
            do {
                try await AppleMusicRatingAccess.setRating(rating) { _ in response }
                XCTFail("Unavailable tracks must not report a successful rating change")
            } catch is AppleMusicRatingAccess.RatingError {
            }
        }
    }

    func testScriptErrorsReachTheCaller() async throws {
        let rating = try XCTUnwrap(MusicTrackRating(trackID: "0123456789ABCDEF", value: 60))
        let failure = NSError(domain: "RatingTest", code: -1743)
        do {
            try await AppleMusicRatingAccess.setRating(rating) { _ in throw failure }
            XCTFail("Script failures must reach the UI")
        } catch {
            XCTAssertEqual(error as NSError, failure)
        }
    }

    func testRatingIsOptInAndSavedControlLayoutsStillDecode() throws {
        XCTAssertFalse(MusicControlButton.defaultLayout.contains(.rating))
        XCTAssertTrue(MusicControlButton.pickerOptions.contains(.rating))
        let saved = Data("[\"previous\",\"playPause\",\"next\",\"favorite\"]".utf8)
        XCTAssertEqual(try JSONDecoder().decode([MusicControlButton].self, from: saved), [.previous, .playPause, .next, .favorite])
    }
}
