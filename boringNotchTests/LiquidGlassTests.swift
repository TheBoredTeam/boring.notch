//
//  LiquidGlassTests.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
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

    @MainActor
    func testReduceTransparencyKeepsEnabledBackgroundOpaque() throws {
        guard LiquidGlassAvailability.isSupported else {
            throw XCTSkip("The host cannot render the glass backdrop")
        }

        let wasEnabled = Defaults[.enableLiquidGlass]
        Defaults[.enableLiquidGlass] = true
        defer { Defaults[.enableLiquidGlass] = wasEnabled }

        func containsBackdrop(_ view: NSView) -> Bool {
            view is LiquidGlassBackdropView || view.subviews.contains(where: containsBackdrop)
        }

        let background = LiquidGlassNotchBackground(
            shape: NotchShape(),
            topRadius: 19,
            bottomRadius: 24
        )
        .frame(width: 200, height: 190)
        // Use SwiftUI's writable override without changing the system setting.
        let hostingView = NSHostingView(
            rootView: background.environment(\._accessibilityReduceTransparency, false)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 190),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertTrue(containsBackdrop(hostingView))

        hostingView.rootView = background.environment(\._accessibilityReduceTransparency, true)
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertFalse(containsBackdrop(hostingView))

        hostingView.rootView = background.environment(\._accessibilityReduceTransparency, false)
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertTrue(containsBackdrop(hostingView))
    }

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
