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

    func testShelfClampsToTheLeftAndRightEdges() {
        let left = FloatingShelfPlacement.frame(cursor: CGPoint(x: 0, y: 450), screenFrame: screen)
        let right = FloatingShelfPlacement.frame(cursor: CGPoint(x: screen.maxX, y: 450), screenFrame: screen)
        XCTAssertEqual(left.minX, screen.minX + FloatingShelfPlacement.screenMargin, accuracy: 0.1)
        XCTAssertEqual(right.maxX, screen.maxX - FloatingShelfPlacement.screenMargin, accuracy: 0.1)
    }

    // MARK: - Trigger

    func testTriggerRequiresShelfFlagsAndAnActiveDrag() {
        XCTAssertFalse(FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: false, floatingShelfEnabled: true, contentDragActive: true,
            shake: true, shiftHeld: true, shortcutPressed: true
        ))
        XCTAssertFalse(FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingShelfEnabled: false, contentDragActive: true,
            shake: true, shiftHeld: false, shortcutPressed: false
        ))
        XCTAssertFalse(FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingShelfEnabled: true, contentDragActive: false,
            shake: true, shiftHeld: true, shortcutPressed: true
        ))
    }

    func testControlShiftChordIsNotShiftAlone() {
        let shiftOnly = HeldModifiers(shift: true)
        let controlShift = HeldModifiers(shift: true, control: true)
        XCTAssertNotEqual(shiftOnly, controlShift)
        XCTAssertTrue(shiftOnly.shift)
        XCTAssertFalse(shiftOnly.control)
    }

    func testEachTriggerCanPresentOnItsOwn() {
        XCTAssertTrue(presenting(shake: true, shiftHeld: false, shortcutPressed: false))
        XCTAssertTrue(presenting(shake: false, shiftHeld: true, shortcutPressed: false))
        XCTAssertTrue(presenting(shake: false, shiftHeld: false, shortcutPressed: true))
        XCTAssertFalse(FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingShelfEnabled: true, contentDragActive: true,
            shake: false, shiftHeld: false, shortcutPressed: false
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
        step: TimeInterval = 0.05
    ) -> Bool {
        let positions: [CGFloat] = [0, 40, 0, 40, 0]
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

    private func presenting(shake: Bool, shiftHeld: Bool, shortcutPressed: Bool) -> Bool {
        FloatingShelfTriggerPolicy.shouldPresent(
            shelfEnabled: true,
            floatingShelfEnabled: true,
            contentDragActive: true,
            shake: shake,
            shiftHeld: shiftHeld,
            shortcutPressed: shortcutPressed
        )
    }

    private func makePasteboard() -> NSPasteboard {
        let name = NSPasteboard.Name("boringNotch.tests.\(UUID().uuidString)")
        return NSPasteboard(name: name)
    }
}
