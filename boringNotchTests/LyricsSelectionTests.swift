//
//  LyricsSelectionTests.swift
//  boringNotchTests
//

import XCTest
@testable import boringNotch

@MainActor
final class LyricsSelectionTests: XCTestCase {
    func testWebSyncedLyricsReplaceNativePlainText() async {
        let service = LyricsService(nativeFetcher: { _, _ in "Native first\nNative second" }, webFetcher: { _, _ in
            ("Web first\nWeb second", [(0, "Web first"), (5, "Web second")])
        })
        await service.fetchLyrics(bundleIdentifier: MediaAppBundleID.appleMusic, title: "Song", artist: "Artist")
        XCTAssertEqual(service.lyricLine(at: 6), "Web second")
        XCTAssertFalse(service.isFetchingLyrics)
    }

    func testNativeLRCIsUsedWithoutWebLookup() async {
        var webCalls = 0
        let service = LyricsService(nativeFetcher: { _, _ in "[00:00.5]First\n[00:02.50]Second" }, webFetcher: { _, _ in
            webCalls += 1
            return ("", [])
        })
        await service.fetchLyrics(bundleIdentifier: MediaAppBundleID.appleMusic, title: "Song", artist: "Artist")
        XCTAssertEqual(webCalls, 0)
        XCTAssertEqual(service.syncedLyrics.map(\.time), [0.5, 2.5])
        XCTAssertEqual(service.lyricLineContext(at: 1).endTime, 2.5)
        XCTAssertEqual(service.lyricLine(at: 3), "Second")
    }

    func testOfflineFallbackRetainsEveryNativeLineAndCanRetry() async {
        var webCalls = 0
        let plain = "First line\nSecond line\nThird line"
        let service = LyricsService(nativeFetcher: { _, _ in plain }, webFetcher: { _, _ in
            webCalls += 1
            return ("", [])
        })
        await service.fetchLyrics(bundleIdentifier: MediaAppBundleID.appleMusic, title: "Song", artist: "Artist")
        XCTAssertEqual(service.lyricLine(at: 100), plain)
        XCTAssertTrue(service.syncedLyrics.isEmpty)
        await service.fetchLyrics(bundleIdentifier: MediaAppBundleID.appleMusic, title: "Song", artist: "Artist")
        XCTAssertEqual(webCalls, 2)
    }

    func testNativePlainTextIsVisibleWhileWebLookupIsPending() async {
        var finish: CheckedContinuation<LyricsService.LyricsResult, Never>?
        let started = expectation(description: "Web lookup started")
        let service = LyricsService(nativeFetcher: { _, _ in "Native plain" }, webFetcher: { _, _ in
            await withCheckedContinuation { continuation in
                finish = continuation
                started.fulfill()
            }
        })
        let fetch = Task { await service.fetchLyrics(bundleIdentifier: MediaAppBundleID.appleMusic, title: "Song", artist: "Artist") }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(service.currentLyrics, "Native plain")
        XCTAssertTrue(service.isFetchingLyrics)
        finish?.resume(returning: ("", []))
        await fetch.value
        XCTAssertFalse(service.isFetchingLyrics)
    }

    func testLateWebResultCannotReplaceNewTrack() async {
        var finishOld: CheckedContinuation<LyricsService.LyricsResult, Never>?
        let started = expectation(description: "Old lookup started")
        let service = LyricsService(nativeFetcher: { _, _ in nil }, webFetcher: { title, _ in
            if title == "Old" {
                return await withCheckedContinuation { continuation in
                    finishOld = continuation
                    started.fulfill()
                }
            }
            return ("New lyrics", [(0, "New lyrics")])
        })
        let old = Task { await service.fetchLyrics(bundleIdentifier: "player", title: "Old", artist: "Artist") }
        await fulfillment(of: [started], timeout: 1)
        await service.fetchLyrics(bundleIdentifier: "player", title: "New", artist: "Artist")
        finishOld?.resume(returning: ("Old lyrics", [(0, "Old lyrics")]))
        await old.value
        XCTAssertEqual(service.currentLyrics, "New lyrics")
        XCTAssertEqual(service.lyricLine(at: 10), "New lyrics")
    }

    func testClearRejectsPendingNativeResult() async {
        var finish: CheckedContinuation<String?, Never>?
        let started = expectation(description: "Native lookup started")
        let service = LyricsService(nativeFetcher: { _, _ in
            await withCheckedContinuation { continuation in
                finish = continuation
                started.fulfill()
            }
        }, webFetcher: { _, _ in XCTFail("Canceled lookup must not start web request"); return ("", []) })
        let fetch = Task { await service.fetchLyrics(bundleIdentifier: MediaAppBundleID.appleMusic, title: "Song", artist: "Artist") }
        await fulfillment(of: [started], timeout: 1)
        service.clearLyrics()
        finish?.resume(returning: "Old native lyrics")
        await fetch.value
        XCTAssertTrue(service.currentLyrics.isEmpty)
        XCTAssertTrue(service.syncedLyrics.isEmpty)
        XCTAssertFalse(service.isFetchingLyrics)
    }

    func testCacheSeparatesSourceAndAmbiguousTitleArtistPairs() async {
        var webCalls = 0
        let service = LyricsService(nativeFetcher: { _, _ in "Native lyrics" }, webFetcher: { title, artist in
            webCalls += 1
            return ("\(title) / \(artist)", [])
        })
        await service.fetchLyrics(bundleIdentifier: "player", title: "A|B", artist: "C")
        await service.fetchLyrics(bundleIdentifier: "player", title: "A", artist: "B|C")
        XCTAssertEqual(service.currentLyrics, "A / B|C")
        await service.fetchLyrics(bundleIdentifier: MediaAppBundleID.appleMusic, title: "A", artist: "B|C")
        XCTAssertEqual(service.currentLyrics, "Native lyrics")
        XCTAssertEqual(webCalls, 3)
        await service.fetchLyrics(bundleIdentifier: "player", title: "A", artist: "B|C")
        XCTAssertEqual(service.currentLyrics, "A / B|C")
        XCTAssertEqual(webCalls, 3)
    }
}
