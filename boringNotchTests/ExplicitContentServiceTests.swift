//
//  ExplicitContentServiceTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class ExplicitContentServiceTests: XCTestCase {
    func testExplicitCatalogValueIsExplicit() {
        XCTAssertTrue(
            ExplicitContentService.isExplicitPlayback(
                catalogExplicitness: .explicit,
                playingTitle: "WAP",
                playingAlbum: "WAP - Single"
            )
        )
    }

    func testCleanedCatalogIsExplicitUnlessPlayingCleanEdit() {
        XCTAssertTrue(
            ExplicitContentService.isExplicitPlayback(
                catalogExplicitness: .cleaned,
                playingTitle: "WAP (feat. Megan Thee Stallion)",
                playingAlbum: "WAP (feat. Megan Thee Stallion) - Single"
            )
        )
        XCTAssertFalse(
            ExplicitContentService.isExplicitPlayback(
                catalogExplicitness: .cleaned,
                playingTitle: "WAP (Clean)",
                playingAlbum: "WAP - Single"
            )
        )
    }

    func testNotExplicitCatalogIsNeverExplicit() {
        XCTAssertFalse(
            ExplicitContentService.isExplicitPlayback(
                catalogExplicitness: .notExplicit,
                playingTitle: "Blinding Lights",
                playingAlbum: "After Hours"
            )
        )
        XCTAssertFalse(
            ExplicitContentService.isExplicitPlayback(
                catalogExplicitness: nil,
                playingTitle: "Unknown",
                playingAlbum: ""
            )
        )
    }

    func testLooksLikeCleanEditMarkers() {
        XCTAssertTrue(ExplicitContentService.looksLikeCleanEdit(title: "Song (Clean)", album: ""))
        XCTAssertTrue(ExplicitContentService.looksLikeCleanEdit(title: "Song", album: "Album [Clean]"))
        XCTAssertTrue(ExplicitContentService.looksLikeCleanEdit(title: "Song - Clean", album: ""))
        XCTAssertFalse(ExplicitContentService.looksLikeCleanEdit(title: "Cleaning Out My Closet", album: ""))
    }

    func testBestMatchPrefersDurationAndExactNames() {
        let results = [
            iTunesSearchTrack(
                trackName: "WHATS POPPIN",
                artistName: "Jack Harlow",
                collectionName: "Other Album",
                trackTimeMillis: 200_000,
                trackExplicitnessRaw: "cleaned"
            ),
            iTunesSearchTrack(
                trackName: "WHATS POPPIN",
                artistName: "Jack Harlow",
                collectionName: "Sweet Action",
                trackTimeMillis: 139_741,
                trackExplicitnessRaw: "cleaned"
            ),
            iTunesSearchTrack(
                trackName: "Whats Poppin Karaoke",
                artistName: "Someone Else",
                collectionName: "Karaoke",
                trackTimeMillis: 139_000,
                trackExplicitnessRaw: "notExplicit"
            ),
        ]

        let best = ExplicitContentService.bestMatch(
            in: results,
            title: "WHATS POPPIN",
            artist: "Jack Harlow",
            album: "Sweet Action",
            duration: 139.7
        )

        XCTAssertEqual(best?.collectionName, "Sweet Action")
        XCTAssertEqual(best?.trackExplicitness, .cleaned)
    }

    func testBestMatchRejectsWeakHits() {
        let results = [
            iTunesSearchTrack(
                trackName: "Totally Different Song",
                artistName: "Other Artist",
                collectionName: "Misc",
                trackTimeMillis: 180_000,
                trackExplicitnessRaw: "explicit"
            )
        ]

        let best = ExplicitContentService.bestMatch(
            in: results,
            title: "WAP",
            artist: "Cardi B",
            album: "",
            duration: 187.5
        )

        XCTAssertNil(best)
    }
}
