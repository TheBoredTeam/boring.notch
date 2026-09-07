//
//  MusicVisualizerTests.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import XCTest
@testable import boringNotch

final class MusicVisualizerTests: XCTestCase {
    @MainActor
    func testRealtimeModeWaitsWithoutSyntheticMotion() throws {
        let visualizer = MusicVisualizerModel()
        visualizer.setUseRealtime(true)
        visualizer.setPlaying(true)
        let bars = try XCTUnwrap(visualizer.layer?.sublayers)

        XCTAssertEqual(bars.count, 6)
        XCTAssertTrue(bars.allSatisfy { $0.animation(forKey: "scaleAnimation") == nil })
    }

    @MainActor
    func testEnablingRealtimeCancelsLegacyMotion() throws {
        let visualizer = MusicVisualizerModel()
        visualizer.setPlaying(true)
        let bars = try XCTUnwrap(visualizer.layer?.sublayers)
        XCTAssertTrue(bars.allSatisfy { $0.animation(forKey: "scaleAnimation") != nil })

        visualizer.setUseRealtime(true)
        XCTAssertTrue(bars.allSatisfy { $0.animation(forKey: "scaleAnimation") == nil })

        visualizer.setUseRealtime(false)
        XCTAssertTrue(bars.allSatisfy { $0.animation(forKey: "scaleAnimation") != nil })
    }
}
