//
//  LowBatteryStateTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class LowBatteryStateTests: XCTestCase {
    private func input(
        level: Int,
        threshold: Int = 20,
        pluggedIn: Bool = false,
        hasBattery: Bool = true,
        enabled: Bool = true
    ) -> LowBatteryState.Input {
        LowBatteryState.Input(
            hasBattery: hasBattery,
            isPluggedIn: pluggedIn,
            level: level,
            threshold: threshold,
            enabled: enabled
        )
    }

    // MARK: - Crossing into the low-battery range

    func testFiresOnceWhenCrossingThreshold() {
        var state = LowBatteryState()

        XCTAssertFalse(state.update(input(level: 100)))
        XCTAssertFalse(state.update(input(level: 50)))
        XCTAssertFalse(state.update(input(level: 25)))
        XCTAssertTrue(state.update(input(level: 20)), "Should fire on reaching the threshold")
    }

    func testDoesNotRepeatWhileStayingLow() {
        var state = LowBatteryState()

        XCTAssertTrue(state.update(input(level: 20)))
        // The exact spam case from the brief: repeated updates at the same and lower levels.
        for level in [19, 19, 18, 18, 17, 5, 1] {
            XCTAssertFalse(
                state.update(input(level: level)),
                "Should not re-fire at \(level)%"
            )
        }
    }

    func testFiresWhenLevelJumpsPastThreshold() {
        var state = LowBatteryState()

        XCTAssertFalse(state.update(input(level: 30)))
        // A sleep/wake gap can skip the threshold entirely.
        XCTAssertTrue(state.update(input(level: 12)))
    }

    // MARK: - Re-arming

    func testRearmsAfterChargingAboveThreshold() {
        var state = LowBatteryState()

        XCTAssertTrue(state.update(input(level: 18)))
        XCTAssertFalse(state.update(input(level: 17)))

        // Charging back up re-arms, then a later discharge warns again.
        XCTAssertFalse(state.update(input(level: 60, pluggedIn: true)))
        XCTAssertFalse(state.update(input(level: 60)))
        XCTAssertTrue(state.update(input(level: 19)))
    }

    func testDoesNotRearmWithinHysteresisMargin() {
        var state = LowBatteryState()

        XCTAssertTrue(state.update(input(level: 20)))
        // Hovering just above the threshold must not re-arm — this is the flapping case.
        for level in [21, 22, 25, 19, 21, 20] {
            XCTAssertFalse(
                state.update(input(level: level)),
                "Should not re-fire while flapping around the threshold (\(level)%)"
            )
        }

        // Clearly above threshold + margin re-arms.
        XCTAssertFalse(state.update(input(level: 26)))
        XCTAssertTrue(state.update(input(level: 20)))
    }

    func testPluggingInReArmsEvenWhileStillLow() {
        var state = LowBatteryState()

        XCTAssertTrue(state.update(input(level: 15)))
        XCTAssertFalse(state.update(input(level: 15, pluggedIn: true)))
        // Unplugging again while still low warns once more — the user chose to go mobile.
        XCTAssertTrue(state.update(input(level: 15)))
    }

    func testNeverFiresWhilePluggedIn() {
        var state = LowBatteryState()

        for level in [30, 20, 10, 5, 1] {
            XCTAssertFalse(state.update(input(level: level, pluggedIn: true)))
        }
    }

    // MARK: - Configuration

    func testChangingThresholdReArms() {
        var state = LowBatteryState()

        XCTAssertTrue(state.update(input(level: 20, threshold: 20)))
        XCTAssertFalse(state.update(input(level: 20, threshold: 20)))

        // Raising the threshold is a fresh decision, so 20% is low again.
        XCTAssertTrue(state.update(input(level: 20, threshold: 30)))
    }

    func testDisabledNeverFiresAndResets() {
        var state = LowBatteryState()

        XCTAssertFalse(state.update(input(level: 10, enabled: false)))
        XCTAssertFalse(state.isWarningActive)

        // Re-enabling behaves like a fresh start rather than staying suppressed.
        XCTAssertTrue(state.update(input(level: 10)))
    }

    // MARK: - Macs without a battery

    func testNeverFiresWithoutABattery() {
        var state = LowBatteryState()

        // A desktop Mac reports a placeholder 0% — it must stay silent.
        for _ in 0..<5 {
            XCTAssertFalse(state.update(input(level: 0, hasBattery: false)))
        }
        XCTAssertFalse(state.isWarningActive)
    }
}
