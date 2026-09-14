//
//  TestHostTests.swift
//  boringNotchTests
//

import XCTest
@testable import boringNotch

final class TestHostTests: XCTestCase {
    func testSharedSchemeEnablesIdleHost() {
        XCTAssertTrue(
            ApplicationRuntime.isTestHost,
            "Run tests through the shared boringNotch scheme so normal app services stay idle."
        )
    }
}
