//
//  MusicVisualizerTests.swift
//  boringNotchTests
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import XCTest
@testable import boringNotch

@MainActor
final class MusicVisualizerTests: XCTestCase {
    private func barFrames(in view: MusicVisualizerModel) -> [CGRect] {
        (view.layer?.sublayers ?? []).map(\.frame)
    }

    func testBarsStayInsideViewShorterThanFullBarHeight() {
        let view = MusicVisualizerModel()
        view.setFrameSize(NSSize(width: 18, height: 10))
        view.setPlaying(true)

        let bars = barFrames(in: view)
        XCTAssertFalse(bars.isEmpty)
        for bar in bars {
            XCTAssertGreaterThanOrEqual(bar.minY, 0)
            XCTAssertLessThanOrEqual(bar.maxY, view.bounds.height)
        }
    }

    func testBarsRefitWhenViewShrinksWhilePlaying() {
        let view = MusicVisualizerModel()
        view.setPlaying(true)
        view.setFrameSize(NSSize(width: 18, height: 6))

        for bar in barFrames(in: view) {
            XCTAssertGreaterThanOrEqual(bar.minY, 0)
            XCTAssertLessThanOrEqual(bar.maxY, view.bounds.height)
        }
    }

    func testBarsKeepFullHeightInTallerView() {
        let view = MusicVisualizerModel()
        view.setFrameSize(NSSize(width: 18, height: 22))
        view.setPlaying(true)

        for bar in view.layer?.sublayers ?? [] {
            XCTAssertEqual(bar.bounds.height, 14)
            XCTAssertEqual(bar.position.y, 11)
        }
    }
}
