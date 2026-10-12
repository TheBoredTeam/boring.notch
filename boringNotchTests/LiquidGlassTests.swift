//
//  LiquidGlassTests.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
import XCTest
import AppKit
import SwiftUI
import Defaults
@testable import boringNotch

final class LiquidGlassScrimTests: XCTestCase {

    private let fadeStart: CGFloat = 80
    private let fadeEndOpacity: CGFloat = 0.23
    private let solidBlackHeight: CGFloat = 32

    private func opacities(_ stops: [Gradient.Stop]) -> [Double] {
        stops.map { NSColor($0.color).alphaComponent }
    }

    /// The scrim is one ramp: locations ascend, opacity only ever falls, and it
    /// starts fully opaque in the solid band and ends on `bottom` at the
    /// bottom edge of the surface.
    private func assertSingleRamp(_ stops: [Gradient.Stop], endingAt bottom: Double) {
        let alphas = opacities(stops)

        XCTAssertEqual(stops.first?.location ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(stops.last?.location ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(alphas.first ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(alphas.last ?? -1, bottom, accuracy: 0.0001)

        for (previous, next) in zip(stops, stops.dropFirst()) {
            XCTAssertLessThanOrEqual(previous.location, next.location)
        }
        for (previous, next) in zip(alphas, alphas.dropFirst()) {
            XCTAssertLessThanOrEqual(next, previous + 0.0001)
        }
    }

    func testOpenedNotchStaysOpaqueToTheFadeStartThenFadesToTheBottomEdge() {
        let totalHeight: CGFloat = 190
        let stops = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: totalHeight,
            fadeStart: fadeStart,
            solidBlackHeight: solidBlackHeight,
            fadeEndOpacity: fadeEndOpacity
        )

        // Everything above the fade start is fully opaque, and the fade into the
        // glass is one monotonic ramp from there to the bottom edge of the surface.
        XCTAssertEqual(stops[0].color, .black)
        XCTAssertEqual(stops[1].color, .black)
        XCTAssertEqual(stops[1].location, fadeStart / totalHeight, accuracy: 0.0001)
        assertSingleRamp(stops, endingAt: Double(fadeEndOpacity))
    }

    func testRampLandsOnFadeEndOpacityAtTheBottomEdge() {
        let stops = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190,
            fadeStart: fadeStart,
            solidBlackHeight: solidBlackHeight,
            fadeEndOpacity: fadeEndOpacity
        )

        XCTAssertEqual(opacities(stops).last ?? -1, Double(fadeEndOpacity), accuracy: 0.0001)
        XCTAssertEqual(stops.last?.location ?? -1, 1, accuracy: 0.0001)
    }

    func testLaterFadeStartLeavesLessRoomForTheRamp() {
        let shallow = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190, fadeStart: 40, solidBlackHeight: solidBlackHeight,
            fadeEndOpacity: fadeEndOpacity
        )
        let deep = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190, fadeStart: 140, solidBlackHeight: solidBlackHeight,
            fadeEndOpacity: fadeEndOpacity
        )

        // Both ramps end at the bottom edge; a later fade start just gets there
        // faster, which is the whole point of splitting the two controls.
        XCTAssertEqual(shallow[1].location, 40.0 / 190.0, accuracy: 0.0001)
        XCTAssertEqual(deep[1].location, 140.0 / 190.0, accuracy: 0.0001)
        assertSingleRamp(shallow, endingAt: Double(fadeEndOpacity))
        assertSingleRamp(deep, endingAt: Double(fadeEndOpacity))
    }

    /// The shipped default fade start is shorter than every closed notch height,
    /// so the surface has to clamp it: without that the closed notch renders a
    /// ramp and the desktop shows through the camera housing.
    func testClosedNotchStaysSolidBlackWithTheShippedDefault() {
        let defaultFadeStart = CGFloat(Defaults.Keys.glassFadeStart.defaultValue)
        let defaultFadeEndOpacity = CGFloat(Defaults.Keys.glassFadeEndOpacity.defaultValue)

        for closedHeight in [CGFloat(32), CGFloat(38), CGFloat(45)] {
            let stops = NotchScrimCalculator.hardwareScrimStops(
                totalHeight: closedHeight,
                fadeStart: defaultFadeStart,
                solidBlackHeight: closedHeight,
                fadeEndOpacity: defaultFadeEndOpacity
            )

            XCTAssertEqual(
                stops.count, 2,
                "closed height \(closedHeight) with the default fade start must stay solid black"
            )
            XCTAssertEqual(stops[0].color, .black)
            XCTAssertEqual(stops[1].color, .black)
        }
    }

    func testFadeNeverStartsAboveTheClosedNotchHeight() {
        let stops = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190,
            fadeStart: 20,
            solidBlackHeight: 38,
            fadeEndOpacity: fadeEndOpacity
        )

        XCTAssertEqual(stops[1].location, 38.0 / 190.0, accuracy: 0.0001)
        assertSingleRamp(stops, endingAt: Double(fadeEndOpacity))
    }

    func testDegenerateHeightStillReturnsStops() {
        for totalHeight in [CGFloat(0), CGFloat(-100)] {
            let stops = NotchScrimCalculator.hardwareScrimStops(
                totalHeight: totalHeight,
                fadeStart: fadeStart,
                solidBlackHeight: solidBlackHeight,
                fadeEndOpacity: fadeEndOpacity
            )

            XCTAssertEqual(stops.count, 2)
        }
    }

    func testFadeEndOpacityIsClampedToValidRange() {
        let opaque = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190, fadeStart: fadeStart, solidBlackHeight: solidBlackHeight,
            fadeEndOpacity: 2
        )
        assertSingleRamp(opaque, endingAt: 1)

        let clear = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190, fadeStart: fadeStart, solidBlackHeight: solidBlackHeight,
            fadeEndOpacity: -1
        )
        assertSingleRamp(clear, endingAt: 0)
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
        XCTAssertTrue(LiquidGlassParameters.fadeStartRange.contains(Defaults.Keys.glassFadeStart.defaultValue))
        XCTAssertTrue(LiquidGlassParameters.fadeEndOpacityRange.contains(Defaults.Keys.glassFadeEndOpacity.defaultValue))
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
            bottomRadius: 24,
            closedNotchHeight: 32
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
