//
//  LiquidGlassTests.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  The scrim is the only part of Liquid Glass that is pure arithmetic, and it is
//  also the part that keeps the camera housing concealed — so it is the part worth
//  pinning down here.
//

import XCTest
import SwiftUI
import Defaults
@testable import boringNotch

final class LiquidGlassScrimTests: XCTestCase {

    private let coreHeight: CGFloat = 80
    private let fadeSoftness: CGFloat = 100
    private let floorTransparency: CGFloat = 0.23

    func testOpenedNotchHoldsCameraCoreOpaqueThenFades() {
        let totalHeight: CGFloat = 190
        let stops = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: totalHeight,
            coreHeight: coreHeight,
            fadeSoftness: fadeSoftness,
            floorTransparency: floorTransparency
        )

        XCTAssertEqual(stops.count, 6)
        XCTAssertEqual(stops[0].location, 0, accuracy: 0.0001)
        XCTAssertEqual(stops[1].location, coreHeight / totalHeight, accuracy: 0.0001)
        XCTAssertEqual(stops.last?.location ?? -1, 1, accuracy: 0.0001)

        // The camera core is fully opaque; the fade that follows is monotonic.
        XCTAssertEqual(stops[0].color, .black)
        XCTAssertEqual(stops[1].color, .black)
        XCTAssertEqual(stops[2].color, Color.black.opacity(0.65))
        XCTAssertEqual(stops[3].color, Color.black.opacity(0.18))
        XCTAssertEqual(stops[4].color, Color.black.opacity(Double(floorTransparency)))
    }

    func testOpenedNotchFloorReachesTheBottomEdge() {
        let stops = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190,
            coreHeight: coreHeight,
            fadeSoftness: fadeSoftness,
            floorTransparency: floorTransparency
        )

        XCTAssertEqual(stops[4].color, stops[5].color)
        XCTAssertEqual(stops.last?.location, 1)
    }

    func testClosedHeightIsSolidBlack() {
        // 38pt closed notch, and anything else at or under the camera core.
        for totalHeight in [CGFloat(38), CGFloat(80)] {
            let stops = NotchScrimCalculator.hardwareScrimStops(
                totalHeight: totalHeight,
                coreHeight: coreHeight,
                fadeSoftness: fadeSoftness,
                floorTransparency: floorTransparency
            )

            XCTAssertEqual(stops.count, 2, "height \(totalHeight) should be solid black")
            XCTAssertEqual(stops[0].color, .black)
            XCTAssertEqual(stops[1].color, .black)
        }
    }

    func testDegenerateHeightStillReturnsStops() {
        for totalHeight in [CGFloat(0), CGFloat(-100)] {
            let stops = NotchScrimCalculator.hardwareScrimStops(
                totalHeight: totalHeight,
                coreHeight: coreHeight,
                fadeSoftness: fadeSoftness,
                floorTransparency: floorTransparency
            )

            XCTAssertEqual(stops.count, 2)
        }
    }

    func testFloorIsClampedToHalfOpacity() {
        let tooDark = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190,
            coreHeight: coreHeight,
            fadeSoftness: fadeSoftness,
            floorTransparency: 0.9
        )
        XCTAssertEqual(tooDark.last?.color, Color.black.opacity(0.5))

        let negative = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190,
            coreHeight: coreHeight,
            fadeSoftness: fadeSoftness,
            floorTransparency: -1
        )
        XCTAssertEqual(negative.last?.color, Color.black.opacity(0))
    }
}

final class LiquidGlassParametersTests: XCTestCase {

    /// A default outside its own slider range would make the control jump the
    /// first time it is touched, so the two have to agree.
    func testDefaultsAreInsideTheirRanges() {
        XCTAssertTrue(LiquidGlassParameters.refractionRange.contains(Defaults.Keys.glassRefraction.defaultValue))
        XCTAssertTrue(LiquidGlassParameters.blurRange.contains(Defaults.Keys.glassBlur.defaultValue))
        XCTAssertTrue(LiquidGlassParameters.dispersionRange.contains(Defaults.Keys.glassDispersion.defaultValue))
        XCTAssertTrue(LiquidGlassParameters.lensHeightRange.contains(Defaults.Keys.glassLensHeight.defaultValue))
        XCTAssertTrue(LiquidGlassParameters.coreHeightRange.contains(Defaults.Keys.glassCoreHeight.defaultValue))
        XCTAssertTrue(LiquidGlassParameters.fadeSoftnessRange.contains(Defaults.Keys.glassFadeSoftness.defaultValue))
        XCTAssertTrue(LiquidGlassParameters.floorTransparencyRange.contains(Defaults.Keys.glassFloorTransparency.defaultValue))
    }
}

final class LiquidGlassAvailabilityTests: XCTestCase {

    func testAvailabilityIsStable() {
        XCTAssertEqual(LiquidGlassAvailability.isSupported, LiquidGlassAvailability.isSupported)
    }

    func testAvailabilityIsFalseBeforeMacOS26() throws {
        guard #unavailable(macOS 26.0) else {
            throw XCTSkip("Private CoreAnimation symbols exist on this host")
        }

        XCTAssertFalse(LiquidGlassAvailability.isSupported)
    }
}
