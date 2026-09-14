//
//  WiFiActivityStateTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

final class WiFiActivityStateTests: XCTestCase {
    /// Both activities enabled, which is the shipping default.
    private func flush(
        _ state: inout WiFiActivityState,
        connect: Bool = true,
        disconnect: Bool = true
    ) -> WiFiActivityState.Outcome {
        state.flush(connectEnabled: connect, disconnectEnabled: disconnect)
    }

    /// Bring a state up to a known announced baseline the way `start()` does.
    private func seeded(connected: Bool) -> WiFiActivityState {
        var state = WiFiActivityState()
        state.note(isConnected: connected)
        _ = flush(&state)
        XCTAssertEqual(state.announcedConnected, connected)
        return state
    }

    // MARK: - Seeding

    func testFirstReportWhileConnectedIsSilent() {
        var state = WiFiActivityState()
        state.note(isConnected: true)

        XCTAssertEqual(flush(&state), .none, "Launching already online must not announce")
        XCTAssertEqual(state.announcedConnected, true)
    }

    func testFirstReportWhileDisconnectedIsSilent() {
        var state = WiFiActivityState()
        state.note(isConnected: false)

        XCTAssertEqual(flush(&state), .none)
        XCTAssertEqual(state.announcedConnected, false)
    }

    func testFlushWithNothingNotedIsSilent() {
        var state = seeded(connected: true)

        XCTAssertEqual(flush(&state), .none)
    }

    // MARK: - Transitions

    func testDisconnectIsAnnounced() {
        var state = seeded(connected: true)
        state.note(isConnected: false)

        XCTAssertEqual(flush(&state), .disconnected)
    }

    func testConnectIsAnnounced() {
        var state = seeded(connected: false)
        state.note(isConnected: true)

        XCTAssertEqual(flush(&state), .connected)
    }

    func testRepeatedIdenticalReportsAnnounceOnce() {
        var state = seeded(connected: false)

        state.note(isConnected: true)
        XCTAssertEqual(flush(&state), .connected)

        for _ in 0..<3 {
            state.note(isConnected: true)
            XCTAssertEqual(flush(&state), .none, "A repeat report is not a transition")
        }
    }

    // MARK: - Flap collapsing

    func testDropAndRecoveryWithinOneWindowIsSilent() {
        var state = seeded(connected: true)

        state.note(isConnected: false)
        state.note(isConnected: true)

        XCTAssertEqual(flush(&state), .none, "A reconnect inside the window is not news")
    }

    func testOddNumberOfFlipsAnnouncesTheFinalState() {
        var state = seeded(connected: true)

        state.note(isConnected: false)
        state.note(isConnected: true)
        state.note(isConnected: false)

        XCTAssertEqual(flush(&state), .disconnected)
    }

    func testFlappingUpToConnectedAnnouncesConnected() {
        var state = seeded(connected: false)

        state.note(isConnected: true)
        state.note(isConnected: false)
        state.note(isConnected: true)

        XCTAssertEqual(flush(&state), .connected)
    }

    // MARK: - Settings gates advance the baseline even while muted

    func testMutedConnectStillAdvancesTheBaseline() {
        var state = seeded(connected: false)

        state.note(isConnected: true)
        XCTAssertEqual(flush(&state, connect: false), .none)
        XCTAssertEqual(state.announcedConnected, true, "Bookkeeping must not be gated")

        state.note(isConnected: false)
        XCTAssertEqual(
            flush(&state), .disconnected,
            "The disconnect is still a real transition from the muted connect"
        )
    }

    func testMutedDisconnectStillAdvancesTheBaseline() {
        var state = seeded(connected: true)

        state.note(isConnected: false)
        XCTAssertEqual(flush(&state, disconnect: false), .none)
        XCTAssertEqual(state.announcedConnected, false)

        state.note(isConnected: true)
        XCTAssertEqual(flush(&state), .connected)
    }

    func testBothGatesOffNeverAnnouncesButStillTracks() {
        var state = seeded(connected: true)

        for connected in [false, true, false] {
            state.note(isConnected: connected)
            XCTAssertEqual(flush(&state, connect: false, disconnect: false), .none)
            XCTAssertEqual(state.announcedConnected, connected)
        }
    }

    // MARK: - Sleep and wake

    func testSuppressedFlappingResumesSilentlyOnTheSameNetwork() {
        var state = seeded(connected: true)

        state.suppress()
        state.note(isConnected: false)
        state.note(isConnected: true)
        state.resume()

        XCTAssertEqual(flush(&state), .none, "Waking onto the same network is not news")
    }

    func testWakingWithWiFiGoneRebaselinesThenAnnouncesTheNextChange() {
        var state = seeded(connected: true)

        state.suppress()
        state.note(isConnected: false)
        state.resume()

        XCTAssertEqual(flush(&state), .none)
        XCTAssertEqual(state.announcedConnected, false, "Resume adopts the post-wake state")

        state.note(isConnected: true)
        XCTAssertEqual(flush(&state), .connected)
    }

    func testFlushWhileSuppressedAnnouncesNothingAndKeepsThePendingReport() {
        var state = seeded(connected: true)

        state.suppress()
        state.note(isConnected: false)

        XCTAssertEqual(flush(&state), .none)
        XCTAssertEqual(state.pendingConnected, false, "The report survives for resume()")
    }

    func testResumeWithoutSuppressIsANoOp() {
        var state = seeded(connected: true)

        state.resume()
        state.note(isConnected: false)

        XCTAssertEqual(flush(&state), .disconnected)
    }

    // MARK: - Reset

    func testResetReSeedsWithoutAnnouncing() {
        var state = seeded(connected: true)
        state.reset()

        XCTAssertNil(state.announcedConnected)

        state.note(isConnected: false)
        XCTAssertEqual(flush(&state), .none, "A restart re-seeds rather than announcing")
    }

    // MARK: - RSSI bucketing

    func testSignalStrengthBoundaries() {
        XCTAssertEqual(WiFiSignalStrength(rssi: -30), .excellent)
        XCTAssertEqual(WiFiSignalStrength(rssi: -55), .excellent)
        XCTAssertEqual(WiFiSignalStrength(rssi: -56), .good)
        XCTAssertEqual(WiFiSignalStrength(rssi: -67), .good)
        XCTAssertEqual(WiFiSignalStrength(rssi: -68), .fair)
        XCTAssertEqual(WiFiSignalStrength(rssi: -75), .fair)
        XCTAssertEqual(WiFiSignalStrength(rssi: -76), .weak)
        XCTAssertEqual(WiFiSignalStrength(rssi: -95), .weak)
    }

    func testZeroRSSIIsUnavailableRatherThanExcellent() {
        // CoreWLAN reports 0 when it is not associated, and possibly when the reading is
        // permission-gated. Either way it must not render as a full-strength bar.
        XCTAssertNil(WiFiSignalStrength(rssi: 0))
    }

    func testImplausibleRSSIIsUnavailable() {
        for rssi in [-120, -101, -9, 10, 100] {
            XCTAssertNil(WiFiSignalStrength(rssi: rssi), "\(rssi) dBm should not bucket")
        }
    }

    func testVariableValueIsMonotonicAndNeverZero() {
        let ordered: [WiFiSignalStrength] = [.weak, .fair, .good, .excellent]

        for strength in ordered {
            XCTAssertGreaterThan(strength.variableValue, 0, "0 renders as 'no signal'")
            XCTAssertLessThanOrEqual(strength.variableValue, 1)
        }

        let values = ordered.map(\.variableValue)
        XCTAssertEqual(values, values.sorted(), "Stronger signal must fill more of the glyph")
    }
}
