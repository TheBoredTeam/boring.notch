// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import XCTest
@testable import boringNotch

final class NotchActivityLayoutTests: XCTestCase {
    func testDifferentContentWidthsKeepTheCutoutCentered() {
        let layout = metrics(leading: 120, trailing: 24)

        XCTAssertEqual(layout.sideWidth, 120)
        XCTAssertEqual(layout.protectedWidth, 201)
        XCTAssertEqual(layout.width, 441)
        XCTAssertEqual(layout.width / 2, layout.sideWidth + layout.protectedWidth / 2)
    }

    func testOneSidedActivityKeepsAnEqualEmptyRegionAcrossTheCutout() {
        let layout = metrics(leading: 0, trailing: 30)

        XCTAssertEqual(layout.sideWidth, 30)
        XCTAssertEqual(layout.width, 261)
    }

    func testOversizedContentUsesTheAvailableBudget() {
        let layout = metrics(leading: 10_000, trailing: 28, maximumWidth: 500)

        XCTAssertEqual(layout.sideWidth, 149.5)
        XCTAssertEqual(layout.width, 500)
        XCTAssertEqual(layout.protectedWidth, 201)
    }

    func testNarrowWindowNeverCompressesThePhysicalSafeArea() {
        let layout = metrics(leading: 100, trailing: 100, maximumWidth: 150)

        XCTAssertEqual(layout.sideWidth, 0)
        XCTAssertEqual(layout.width, 201)
    }

    func testInvalidProviderMeasurementsCannotProduceInvalidFrames() {
        let layout = metrics(leading: .nan, trailing: .infinity)

        XCTAssertEqual(layout.sideWidth, 0)
        XCTAssertTrue(layout.width.isFinite)
        XCTAssertGreaterThanOrEqual(layout.width, 185)
    }

    func testInvalidHostDimensionsResolveToFiniteNonnegativeGeometry() {
        let layout = NotchActivityLayoutMetrics(
            safeAreaWidth: -10,
            height: .nan,
            maximumWidth: .infinity,
            clearance: -4,
            leadingWidth: 20,
            trailingWidth: 10
        )

        XCTAssertEqual(layout.width, 0)
        XCTAssertEqual(layout.height, 0)
    }

    func testContentResizeReleasesPreviouslyAllocatedSpace() {
        let expanded = metrics(leading: 136, trailing: 120)
        let compact = metrics(leading: 26, trailing: 18)

        XCTAssertEqual(expanded.width - compact.width, 220)
        XCTAssertEqual(expanded.protectedWidth, compact.protectedWidth)
    }

    private func metrics(
        leading: CGFloat,
        trailing: CGFloat,
        maximumWidth: CGFloat = 640
    ) -> NotchActivityLayoutMetrics {
        NotchActivityLayoutMetrics(
            safeAreaWidth: 185,
            height: 38,
            maximumWidth: maximumWidth,
            leadingWidth: leading,
            trailingWidth: trailing
        )
    }
}
