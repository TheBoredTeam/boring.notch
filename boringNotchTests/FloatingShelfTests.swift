//
//  FloatingShelfTests.swift
//  boringNotchTests
//

import AppKit
import CoreGraphics
import XCTest

@testable import boringNotch

final class FloatingShelfTests: XCTestCase {

    // MARK: - Shake

    func testStraightDragDoesNotShake() {
        var detector = PointerShakeDetector()
        var triggered = false
        for step in 0..<20 {
            let sample = PointerSample(point: CGPoint(x: CGFloat(step) * 20, y: 100), time: Double(step) * 0.02)
            if detector.add(sample) {
                triggered = true
            }
        }
        XCTAssertFalse(triggered)
    }

    func testRapidHorizontalReversalsShake() {
        var detector = PointerShakeDetector()
        XCTAssertTrue(feedShake(&detector, axis: .horizontal, startTime: 0))
    }

    func testRapidVerticalReversalsShake() {
        var detector = PointerShakeDetector()
        XCTAssertTrue(feedShake(&detector, axis: .vertical, startTime: 0))
    }

    func testSlowReversalsDoNotShake() {
        var detector = PointerShakeDetector()
        XCTAssertFalse(feedShake(&detector, axis: .horizontal, startTime: 0, step: 0.4))
    }

    func testJitterDoesNotShake() {
        var detector = PointerShakeDetector()
        var triggered = false
        for step in 0..<12 {
            let x: CGFloat = step.isMultiple(of: 2) ? 0 : 3
            let sample = PointerSample(point: CGPoint(x: x, y: 0), time: Double(step) * 0.03)
            if detector.add(sample) {
                triggered = true
            }
        }
        XCTAssertFalse(triggered)
    }

    func testCooldownBlocksImmediateSecondShake() {
        var detector = PointerShakeDetector()
        XCTAssertTrue(feedShake(&detector, axis: .horizontal, startTime: 0))
        XCTAssertFalse(feedShake(&detector, axis: .horizontal, startTime: 0.1))
        XCTAssertTrue(feedShake(&detector, axis: .horizontal, startTime: 1.2))
    }

    func testSensitivityChangesHowMuchShakeIsNeeded() {
        let short: [CGFloat] = [0, 40, 0, 40]
        let long: [CGFloat] = [0, 40, 0, 40, 0, 40]

        var high = PointerShakeDetector(sensitivity: .high)
        XCTAssertTrue(feedShake(&high, axis: .horizontal, startTime: 0, positions: short))

        var medium = PointerShakeDetector(sensitivity: .medium)
        XCTAssertFalse(feedShake(&medium, axis: .horizontal, startTime: 0, positions: short))

        var low = PointerShakeDetector(sensitivity: .low)
        XCTAssertFalse(feedShake(&low, axis: .horizontal, startTime: 0))
        low.reset()
        XCTAssertTrue(feedShake(&low, axis: .horizontal, startTime: 1, positions: long))
    }

    // MARK: - Placement

    func testShelfSitsBelowThePointer() {
        let frame = FloatingShelfPlacement.frame(cursor: CGPoint(x: 720, y: 450), screenFrame: screen)
        XCTAssertEqual(frame.size, FloatingShelfPlacement.panelSize)
        XCTAssertEqual(frame.midX, 720, accuracy: 0.1)
        XCTAssertEqual(frame.maxY, 450 - FloatingShelfPlacement.cursorGap, accuracy: 0.1)
    }

    func testShelfFlipsAboveThePointerNearTheBottomEdge() {
        let frame = FloatingShelfPlacement.frame(cursor: CGPoint(x: 720, y: 20), screenFrame: screen)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
        XCTAssertGreaterThanOrEqual(frame.minY, 20 + FloatingShelfPlacement.cursorGap)
    }

    func testShelfGrowsFromTheEdgeNearestThePointer() {
        let below = CGPoint(x: 720, y: 450)
        let belowAnchor = FloatingShelfPlacement.growthAnchor(
            cursor: below,
            frame: FloatingShelfPlacement.frame(cursor: below, screenFrame: screen)
        )
        XCTAssertEqual(belowAnchor.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(belowAnchor.y, 0)

        let nearBottomLeft = CGPoint(x: 0, y: 20)
        let aboveAnchor = FloatingShelfPlacement.growthAnchor(
            cursor: nearBottomLeft,
            frame: FloatingShelfPlacement.frame(cursor: nearBottomLeft, screenFrame: screen)
        )
        XCTAssertEqual(aboveAnchor.x, 0)
        XCTAssertEqual(aboveAnchor.y, 1)
    }

    func testShelfClampsToTheLeftAndRightEdges() {
        let left = FloatingShelfPlacement.frame(cursor: CGPoint(x: 0, y: 450), screenFrame: screen)
        let right = FloatingShelfPlacement.frame(cursor: CGPoint(x: screen.maxX, y: 450), screenFrame: screen)
        XCTAssertEqual(left.minX, screen.minX + FloatingShelfPlacement.screenMargin, accuracy: 0.1)
        XCTAssertEqual(right.maxX, screen.maxX - FloatingShelfPlacement.screenMargin, accuracy: 0.1)
    }

    // MARK: - Trigger

    func testTriggerRequiresShelfFlagsAndAnActiveDrag() {
        XCTAssertFalse(FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: false, floatingShelfEnabled: true, notchOpen: false, contentDragActive: true,
            shake: true, shiftHeld: true, shortcutPressed: true
        ))
        XCTAssertFalse(FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingShelfEnabled: false, notchOpen: false, contentDragActive: true,
            shake: true, shiftHeld: false, shortcutPressed: false
        ))
        XCTAssertFalse(FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingShelfEnabled: true, notchOpen: false, contentDragActive: false,
            shake: true, shiftHeld: true, shortcutPressed: false
        ))
    }

    func testShortcutOpensWithoutADrag() {
        XCTAssertTrue(FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingShelfEnabled: true, notchOpen: false, contentDragActive: false,
            shake: false, shiftHeld: false, shortcutPressed: true
        ))
    }

    func testOpenNotchBlocksEveryTrigger() {
        XCTAssertFalse(FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingShelfEnabled: true, notchOpen: true, contentDragActive: true,
            shake: true, shiftHeld: false, shortcutPressed: false
        ))
        XCTAssertFalse(FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingShelfEnabled: true, notchOpen: true, contentDragActive: true,
            shake: false, shiftHeld: true, shortcutPressed: false
        ))
        XCTAssertFalse(FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingShelfEnabled: true, notchOpen: true, contentDragActive: false,
            shake: false, shiftHeld: false, shortcutPressed: true
        ))
    }

    func testDismissWaitsWhileHoveringSharingGrabbingOrInAMenu() {
        XCTAssertFalse(closing(pointerInside: true))
        XCTAssertFalse(closing(sharingActive: true))
        XCTAssertFalse(closing(grabbingItem: true))
        XCTAssertFalse(closing(menuOpen: true))
        XCTAssertTrue(closing())
    }

    func testDismissWaitsUntilThePointerHasVisited() {
        XCTAssertFalse(closing(hasVisited: false))
        XCTAssertFalse(closing(hasVisited: false, pointerInside: true))
    }

    func testShortcutShelfStaysUntilItHasBeenUsed() {
        XCTAssertFalse(closing(hasVisited: true, awaitsUse: true))
        XCTAssertFalse(closing(hasVisited: true, pointerInside: true, awaitsUse: true))
        XCTAssertTrue(closing(awaitsUse: false))
    }

    private func closing(
        hasVisited: Bool = true,
        pointerInside: Bool = false,
        sharingActive: Bool = false,
        grabbingItem: Bool = false,
        menuOpen: Bool = false,
        awaitsUse: Bool = false
    ) -> Bool {
        FloatingShelfDismissPolicy.shouldClose(
            hasVisited: hasVisited,
            pointerInside: pointerInside,
            sharingActive: sharingActive,
            grabbingItem: grabbingItem,
            menuOpen: menuOpen,
            awaitsUse: awaitsUse
        )
    }

    func testEachTriggerCanPresentOnItsOwn() {
        XCTAssertTrue(presenting(shake: true, shiftHeld: false, shortcutPressed: false))
        XCTAssertTrue(presenting(shake: false, shiftHeld: true, shortcutPressed: false))
        XCTAssertTrue(presenting(shake: false, shiftHeld: false, shortcutPressed: true))
        XCTAssertFalse(FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingShelfEnabled: true, notchOpen: false, contentDragActive: true,
            shake: false, shiftHeld: false, shortcutPressed: false
        ))
    }

    func testDisabledTriggersDoNotPresent() {
        XCTAssertFalse(presenting(shake: true, shakeTriggerEnabled: false, shiftHeld: false, shortcutPressed: false))
        XCTAssertFalse(presenting(shake: false, shiftHeld: true, shiftTriggerEnabled: false, shortcutPressed: false))
        XCTAssertTrue(presenting(shake: true, shakeTriggerEnabled: false, shiftHeld: true, shortcutPressed: false))
    }

    func testShortcutIgnoresTheDragTriggerSettings() {
        XCTAssertTrue(presenting(
            shake: false, shakeTriggerEnabled: false,
            shiftHeld: false, shiftTriggerEnabled: false,
            shortcutPressed: true
        ))
    }

    // MARK: - Pasteboard

    func testEmptyPasteboardIsNotDroppable() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        XCTAssertFalse(DragPasteboardContent.isDroppable(pasteboard))
    }

    func testStringPasteboardIsDroppable() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("notes", forType: .string)
        XCTAssertTrue(DragPasteboardContent.isDroppable(pasteboard))
    }

    func testImageWithoutTextOrFileIsNotDroppable() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setData(Data([0, 1, 2, 3]), forType: .tiff)
        XCTAssertFalse(DragPasteboardContent.isDroppable(pasteboard))
    }

    // MARK: - Helpers

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private enum ShakeAxis {
        case horizontal
        case vertical
    }

    private func feedShake(
        _ detector: inout PointerShakeDetector,
        axis: ShakeAxis,
        startTime: TimeInterval,
        step: TimeInterval = 0.05,
        positions: [CGFloat] = [0, 40, 0, 40, 0]
    ) -> Bool {
        var triggered = false
        for (index, position) in positions.enumerated() {
            let point: CGPoint
            switch axis {
            case .horizontal:
                point = CGPoint(x: position, y: 0)
            case .vertical:
                point = CGPoint(x: 0, y: position)
            }
            let sample = PointerSample(point: point, time: startTime + (Double(index) * step))
            if detector.add(sample) {
                triggered = true
            }
        }
        return triggered
    }

    private func presenting(
        shake: Bool,
        shakeTriggerEnabled: Bool = true,
        shiftHeld: Bool,
        shiftTriggerEnabled: Bool = true,
        shortcutPressed: Bool
    ) -> Bool {
        FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: true,
            floatingShelfEnabled: true,
            notchOpen: false,
            contentDragActive: true,
            shake: shake,
            shakeTriggerEnabled: shakeTriggerEnabled,
            shiftHeld: shiftHeld,
            shiftTriggerEnabled: shiftTriggerEnabled,
            shortcutPressed: shortcutPressed
        )
    }

    private func makePasteboard() -> NSPasteboard {
        let name = NSPasteboard.Name("boringNotch.tests.\(UUID().uuidString)")
        return NSPasteboard(name: name)
    }
}
