import XCTest
@testable import boringNotch

final class NotchGeometryTests: XCTestCase {
    func testCapacityAndFiniteSizesAcrossDisplayFixtures() {
        for width in [CGFloat(185), 200, 220] {
            for hardwareHeight in [CGFloat(0), 32, 38] {
                for height in [CGFloat(0), 1, 8, 12, 23, 38, 64] {
                    let geometry = NotchGeometry(closedSize: CGSize(width: width, height: height), hardwareHeight: hardwareHeight)
                    XCTAssertEqual(geometry.closedSize.height, height)
                    XCTAssertEqual(geometry.closedSize.width, width, "Keep measured hardware width")
                    XCTAssertGreaterThanOrEqual(geometry.artworkSize, 0)
                    XCTAssertGreaterThanOrEqual(geometry.inlineLabelWidth, 0)
                    if height == 0 {
                        XCTAssertEqual(geometry.capacity, .hidden)
                        XCTAssertEqual(geometry.contentHeight, 0)
                        XCTAssertEqual(geometry.contentTopInset, 0)
                    } else if height < 24 {
                        XCTAssertEqual(geometry.capacity, .expanded)
                        XCTAssertEqual(geometry.contentHeight, 32)
                        XCTAssertEqual(geometry.contentTopInset, hardwareHeight)
                    } else {
                        XCTAssertEqual(geometry.capacity, .compact)
                        XCTAssertEqual(geometry.contentHeight, height)
                    }
                }
            }
        }
    }

    func testInvalidSizesDoNotProduceNegativeOrInfiniteFrames() {
        for height in [CGFloat(-12), .infinity, .nan] {
            let geometry = NotchGeometry(closedSize: CGSize(width: -100, height: height), hardwareHeight: -1)
            XCTAssertEqual(geometry.closedSize, .zero)
            XCTAssertEqual(geometry.artworkSize, 0)
            XCTAssertTrue(geometry.activationSize.height.isFinite)
        }
    }

    func testClosedActivationDoesNotIncludeFutureExpandedDestination() {
        let geometry = NotchGeometry(closedSize: CGSize(width: 200, height: 38))
        let screen = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        let activation = geometry.activationRect(on: screen)
        XCTAssertTrue(activation.contains(CGPoint(x: screen.midX, y: screen.maxY - 10)))
        XCTAssertFalse(activation.contains(CGPoint(x: screen.midX + 250, y: screen.maxY - 80)), "Tab reorder below and beside closed notch must not activate")
        XCTAssertEqual(activation.maxY, screen.maxY)
    }

    func testZeroHeightHasSeparateActivationStrip() {
        let geometry = NotchGeometry(closedSize: CGSize(width: 185, height: 0))
        XCTAssertEqual(geometry.contentHeight, 0)
        XCTAssertEqual(geometry.activationSize, CGSize(width: 185, height: 10))
    }

    func testInlineLabelsFitAvailablePanelWidth() {
        for width in [CGFloat(185), 220, 350] {
            let geometry = NotchGeometry(closedSize: CGSize(width: width, height: 38), availableWidth: 640)
            XCTAssertLessThanOrEqual(width + 2 * geometry.artworkSize + 64 + 2 * geometry.inlineLabelWidth, 640)
        }
    }

    func testTransientMusicPeekDoesNotRequirePersistentActivity() {
        XCTAssertTrue(ClosedMusicPresentation.isVisible(hasMedia: true, persistentEnabled: false, transientPeek: true, otherExpansion: false))
        XCTAssertFalse(ClosedMusicPresentation.isVisible(hasMedia: true, persistentEnabled: false, transientPeek: false, otherExpansion: false))
        XCTAssertFalse(ClosedMusicPresentation.isVisible(hasMedia: true, persistentEnabled: true, transientPeek: true, otherExpansion: true))
    }
}
