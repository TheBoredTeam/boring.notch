//
//  BrightnessSteppingTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class BrightnessSteppingTests: XCTestCase {
    private let step: Float = 1.0 / 16.0
    private let fineStep: Float = 1.0 / 64.0

    private func press(_ count: Int, from start: Float, delta: Float, step: Float) -> Float {
        var level = start
        for _ in 0..<count {
            level = BrightnessStepping.target(from: level, delta: delta, step: step)
        }
        return level
    }

    func testOnGridLevelMovesOneStep() {
        XCTAssertEqual(BrightnessStepping.target(from: 0.5, delta: step, step: step), 0.5625)
        XCTAssertEqual(BrightnessStepping.target(from: 0.5, delta: -step, step: step), 0.4375)
    }

    func testOffGridLevelSnapsToNextGridPointInKeyDirection() {
        // Ambient light left the backlight at 51%; the next press down must
        // land on 50%, not 44.75%.
        XCTAssertEqual(BrightnessStepping.target(from: 0.51, delta: -step, step: step), 0.5)
        XCTAssertEqual(BrightnessStepping.target(from: 0.51, delta: step, step: step), 0.5625)
        XCTAssertEqual(BrightnessStepping.target(from: 0.49, delta: step, step: step), 0.5)
        XCTAssertEqual(BrightnessStepping.target(from: 0.49, delta: -step, step: step), 0.4375)
    }

    func testFiftyPercentIsReachableFromOffGridLevels() {
        // Without snapping, 0.27 + 4 steps is 0.52 and 0.72 - 4 steps is 0.47,
        // and only hitting 0% or 100% would line the level up again.
        XCTAssertEqual(press(4, from: 0.27, delta: step, step: step), 0.5)
        XCTAssertEqual(press(4, from: 0.72, delta: -step, step: step), 0.5)
        XCTAssertEqual(press(32, from: 0.003, delta: fineStep, step: fineStep), 0.5)
    }

    func testReadBackNoiseCountsAsOnGrid() {
        XCTAssertEqual(BrightnessStepping.target(from: 0.49999, delta: step, step: step), 0.5625)
        XCTAssertEqual(BrightnessStepping.target(from: 0.50001, delta: -step, step: step), 0.4375)
    }

    func testFineStepsUseTheirOwnGrid() {
        XCTAssertEqual(BrightnessStepping.target(from: 0.51, delta: -fineStep, step: fineStep), 0.5)
        XCTAssertEqual(BrightnessStepping.target(from: 0.5, delta: fineStep, step: fineStep), 0.515625)
    }

    func testCoalescedPressesMoveSeveralSteps() {
        XCTAssertEqual(BrightnessStepping.target(from: 0.51, delta: -3 * step, step: step), 0.375)
        XCTAssertEqual(BrightnessStepping.target(from: 0.25, delta: 2 * step, step: step), 0.375)
    }

    func testClampsToValidRange() {
        XCTAssertEqual(BrightnessStepping.target(from: 0.98, delta: step, step: step), 1)
        XCTAssertEqual(BrightnessStepping.target(from: 1, delta: step, step: step), 1)
        XCTAssertEqual(BrightnessStepping.target(from: 0.02, delta: -step, step: step), 0)
        XCTAssertEqual(BrightnessStepping.target(from: 0, delta: -step, step: step), 0)
    }
}
