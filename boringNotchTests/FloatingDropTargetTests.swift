//
//  FloatingDropTargetTests.swift
//  boringNotchTests
//

import AppKit
import CoreGraphics
import Defaults
import XCTest

@testable import boringNotch

final class FloatingDropTargetTests: XCTestCase {

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

    func testDropTargetSitsBelowThePointer() {
        let frame = FloatingDropTargetPlacement.frame(cursor: CGPoint(x: 720, y: 450), screenFrame: screen)
        XCTAssertEqual(frame.size, FloatingDropTargetPlacement.panelSize)
        XCTAssertEqual(frame.midX, 720, accuracy: 0.1)
        XCTAssertEqual(frame.maxY, 450 - FloatingDropTargetPlacement.cursorGap, accuracy: 0.1)
    }

    func testDropTargetFlipsAboveThePointerNearTheBottomEdge() {
        let frame = FloatingDropTargetPlacement.frame(cursor: CGPoint(x: 720, y: 20), screenFrame: screen)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
        XCTAssertGreaterThanOrEqual(frame.minY, 20 + FloatingDropTargetPlacement.cursorGap)
    }

    func testDropTargetGrowsFromTheEdgeNearestThePointer() {
        let below = CGPoint(x: 720, y: 450)
        let belowAnchor = FloatingDropTargetPlacement.growthAnchor(
            cursor: below,
            frame: FloatingDropTargetPlacement.frame(cursor: below, screenFrame: screen)
        )
        XCTAssertEqual(belowAnchor.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(belowAnchor.y, 0)

        let nearBottomLeft = CGPoint(x: 0, y: 20)
        let aboveAnchor = FloatingDropTargetPlacement.growthAnchor(
            cursor: nearBottomLeft,
            frame: FloatingDropTargetPlacement.frame(cursor: nearBottomLeft, screenFrame: screen)
        )
        XCTAssertEqual(aboveAnchor.x, 0)
        XCTAssertEqual(aboveAnchor.y, 1)
    }

    func testDropTargetClampsToTheLeftAndRightEdges() {
        let left = FloatingDropTargetPlacement.frame(cursor: CGPoint(x: 0, y: 450), screenFrame: screen)
        let right = FloatingDropTargetPlacement.frame(cursor: CGPoint(x: screen.maxX, y: 450), screenFrame: screen)
        XCTAssertEqual(left.minX, screen.minX + FloatingDropTargetPlacement.screenMargin, accuracy: 0.1)
        XCTAssertEqual(right.maxX, screen.maxX - FloatingDropTargetPlacement.screenMargin, accuracy: 0.1)
    }

    // MARK: - Trigger

    func testTriggerRequiresShelfFlagsAndAnActiveDrag() {
        XCTAssertFalse(FloatingDropTargetTriggerPolicy.shouldPresent(
            shelfEnabled: false, floatingDropTargetEnabled: true, notchOpen: false, contentDragActive: true,
            shake: true, shiftHeld: true
        ))
        XCTAssertFalse(FloatingDropTargetTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingDropTargetEnabled: false, notchOpen: false, contentDragActive: true,
            shake: true, shiftHeld: false
        ))
        XCTAssertFalse(FloatingDropTargetTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingDropTargetEnabled: true, notchOpen: false, contentDragActive: false,
            shake: true, shiftHeld: true
        ))
    }

    func testOpenNotchBlocksEveryTrigger() {
        XCTAssertFalse(FloatingDropTargetTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingDropTargetEnabled: true, notchOpen: true, contentDragActive: true,
            shake: true, shiftHeld: false
        ))
        XCTAssertFalse(FloatingDropTargetTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingDropTargetEnabled: true, notchOpen: true, contentDragActive: true,
            shake: false, shiftHeld: true
        ))
    }

    func testEachTriggerCanPresentOnItsOwn() {
        XCTAssertTrue(presenting(shake: true, shiftHeld: false))
        XCTAssertTrue(presenting(shake: false, shiftHeld: true))
        XCTAssertFalse(FloatingDropTargetTriggerPolicy.shouldPresent(
            shelfEnabled: true, floatingDropTargetEnabled: true, notchOpen: false, contentDragActive: true,
            shake: false, shiftHeld: false
        ))
    }

    func testDisabledTriggersDoNotPresent() {
        XCTAssertFalse(presenting(shake: true, shakeTriggerEnabled: false, shiftHeld: false))
        XCTAssertFalse(presenting(shake: false, shiftHeld: true, shiftTriggerEnabled: false))
        XCTAssertTrue(presenting(shake: true, shakeTriggerEnabled: false, shiftHeld: true))
    }

    // MARK: - Panel

    @MainActor
    func testPointerExitStaysArmedUntilANewDropSuspendsIt() {
        let panel = FloatingDropTargetPanel()
        panel.dismissWhenPointerLeaves {}
        XCTAssertTrue(panel.isWaitingForPointerExit)

        panel.suspendPointerExit()
        XCTAssertFalse(panel.isWaitingForPointerExit)
    }

    @MainActor
    func testDropTargetSitsAboveTheNotchWindow() {
        let panel = FloatingDropTargetPanel()
        XCTAssertEqual(panel.level.rawValue, BoringNotchSkyLightWindow.windowLevel.rawValue + 1)
        XCTAssertLessThan(panel.level.rawValue, NSWindow.Level.screenSaver.rawValue)
    }

    @MainActor
    func testPreviewSessionRejectsOlderDropsAndPresentations() {
        let session = FloatingDropTargetPreviewSession()
        session.beginPresentation(generation: 1)
        let firstDrop = session.beginDrop()
        let secondDrop = session.beginDrop()

        XCTAssertFalse(session.isCurrent(firstDrop))
        XCTAssertTrue(session.isCurrent(secondDrop))

        session.beginPresentation(generation: 2)
        XCTAssertFalse(session.isCurrent(secondDrop))
    }

    @MainActor
    func testShowDuringHideDoesNotFinishTheInterruptedDismissal() async throws {
        let previousAnimationSetting = Defaults[.enableOpeningAnimation]
        let previousSpeed = Defaults[.animationSpeedMultiplier]
        Defaults[.enableOpeningAnimation] = true
        Defaults[.animationSpeedMultiplier] = 1
        defer {
            Defaults[.enableOpeningAnimation] = previousAnimationSetting
            Defaults[.animationSpeedMultiplier] = previousSpeed
        }

        let panel = FloatingDropTargetPanel()
        panel.show(growingFrom: .zero)
        panel.dropInteraction.dropEvent = true
        var hideCompleted = false
        panel.hide { hideCompleted = true }
        panel.show(growingFrom: .zero)

        try await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(hideCompleted)
        XCTAssertFalse(panel.dropInteraction.dropEvent)
        XCTAssertTrue(panel.isVisible)
        panel.orderOut(nil)
    }

    // MARK: - Pasteboard

    func testEmptyPasteboardIsNotDroppable() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        XCTAssertFalse(ShelfDropService.canAccept(pasteboard))
    }

    func testStringPasteboardIsDroppable() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("notes", forType: .string)
        XCTAssertTrue(ShelfDropService.canAccept(pasteboard))
    }

    func testFileURLPasteboardIsDroppable() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("file:///tmp/example.txt", forType: .fileURL)
        XCTAssertTrue(ShelfDropService.canAccept(pasteboard))
    }

    func testURLPasteboardIsDroppable() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("https://example.com", forType: .URL)
        XCTAssertTrue(ShelfDropService.canAccept(pasteboard))
    }

    func testImageWithoutTextOrFileIsNotDroppable() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setData(Data([0, 1, 2, 3]), forType: .tiff)
        XCTAssertFalse(ShelfDropService.canAccept(pasteboard))
    }

    func testPasteboardRejectsWhenAnyItemIsNotDroppable() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()

        let text = NSPasteboardItem()
        text.setString("notes", forType: .string)
        let image = NSPasteboardItem()
        image.setData(Data([0, 1, 2, 3]), forType: .tiff)

        pasteboard.writeObjects([text, image])
        XCTAssertFalse(ShelfDropService.canAccept(pasteboard))
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
        shiftTriggerEnabled: Bool = true
    ) -> Bool {
        FloatingDropTargetTriggerPolicy.shouldPresent(
            shelfEnabled: true,
            floatingDropTargetEnabled: true,
            notchOpen: false,
            contentDragActive: true,
            shake: shake,
            shakeTriggerEnabled: shakeTriggerEnabled,
            shiftHeld: shiftHeld,
            shiftTriggerEnabled: shiftTriggerEnabled
        )
    }

    private func makePasteboard() -> NSPasteboard {
        let name = NSPasteboard.Name("boringNotch.tests.\(UUID().uuidString)")
        return NSPasteboard(name: name)
    }
}
