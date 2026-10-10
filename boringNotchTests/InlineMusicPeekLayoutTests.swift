import XCTest
@testable import boringNotch

final class InlineMusicPeekLayoutTests: XCTestCase {
    func testFontSizeScalesForSmallCustomNotchHeights() {
        XCTAssertEqual(InlineMusicPeekLayout.fontSize(for: 10), 8)
        XCTAssertEqual(InlineMusicPeekLayout.fontSize(for: 15), 12)
        XCTAssertEqual(InlineMusicPeekLayout.fontSize(for: 23), 13)
    }
}
