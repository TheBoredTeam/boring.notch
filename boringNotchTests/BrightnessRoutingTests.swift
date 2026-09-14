import CoreGraphics
import XCTest
@testable import boringNotch

@MainActor
private final class FakeBrightnessClient: BrightnessHardwareControlling {
    var discoveryCalls = 0
    var targetID: CGDirectDisplayID?
    var values: [CGDirectDisplayID: Float] = [:]
    var authoritativeAdjustment: Float?
    var adjustments: [(Float, CGDirectDisplayID)] = []
    var sets: [(Float, CGDirectDisplayID)] = []
    var suspendedAdjustments: Set<CGDirectDisplayID> = []
    private var adjustmentContinuations: [
        CGDirectDisplayID: CheckedContinuation<BrightnessHardwareResult?, Never>
    ] = [:]

    func displayIDForBrightness() async -> CGDirectDisplayID? {
        discoveryCalls += 1
        return targetID
    }

    func currentScreenBrightness(displayID: CGDirectDisplayID) async -> BrightnessHardwareResult? {
        values[displayID].map { .init(displayID: displayID, brightness: $0) }
    }

    func setScreenBrightness(
        _ value: Float, displayID: CGDirectDisplayID
    ) async -> BrightnessHardwareResult? {
        sets.append((value, displayID))
        guard values[displayID] != nil else { return nil }
        values[displayID] = value
        return .init(displayID: displayID, brightness: value)
    }

    func adjustScreenBrightness(
        by value: Float, displayID: CGDirectDisplayID
    ) async -> BrightnessHardwareResult? {
        adjustments.append((value, displayID))
        if suspendedAdjustments.contains(displayID) {
            return await withCheckedContinuation { adjustmentContinuations[displayID] = $0 }
        }
        guard let current = values[displayID] else { return nil }
        let resulting = authoritativeAdjustment ?? max(0, min(1, current + value))
        values[displayID] = resulting
        return .init(displayID: displayID, brightness: resulting)
    }

    func resumeAdjustment(displayID: CGDirectDisplayID, brightness: Float) {
        suspendedAdjustments.remove(displayID)
        values[displayID] = brightness
        adjustmentContinuations.removeValue(forKey: displayID)?.resume(
            returning: .init(displayID: displayID, brightness: brightness))
    }
}

@MainActor
final class BrightnessRoutingTests: XCTestCase {
    func testStandaloneDispositionPassesThroughDiscoveringAndUnsupportedTargets() async {
        let client = FakeBrightnessClient()
        client.targetID = 7
        client.values[7] = 0.4
        let manager = makeManager(client: client) { _, _ in }
        var normalCalls = 0
        func dispatch() -> Bool {
            MediaKeyInterceptor.dispatchKey(
                keyCode: 2, option: false, shift: false, command: false,
                brightnessSupported: manager.canAdjustBrightness,
                optionAction: { XCTFail("unexpected option action"); return false },
                normalAction: { normalCalls += 1 })
        }
        XCTAssertFalse(dispatch())
        XCTAssertEqual(normalCalls, 0)
        await settle()
        XCTAssertTrue(dispatch())
        XCTAssertEqual(normalCalls, 1)
        client.targetID = nil
        manager.invalidateTopology()
        XCTAssertFalse(dispatch())
        await settle()
        XCTAssertFalse(dispatch())
        XCTAssertEqual(normalCalls, 1)
    }

    func testStandaloneDispositionPreservesCommandAndOptionActions() {
        for keyCode in [2, 3] {
            var normalCalls = 0
            var optionCalls = 0
            let command = MediaKeyInterceptor.dispatchKey(
                keyCode: keyCode, option: false, shift: false, command: true,
                brightnessSupported: false,
                optionAction: { optionCalls += 1; return true },
                normalAction: { normalCalls += 1 })
            XCTAssertTrue(command)
            XCTAssertEqual(normalCalls, 1)
            XCTAssertEqual(optionCalls, 0)
            let option = MediaKeyInterceptor.dispatchKey(
                keyCode: keyCode, option: true, shift: false, command: false,
                brightnessSupported: false,
                optionAction: { optionCalls += 1; return true },
                normalAction: { normalCalls += 1 })
            XCTAssertTrue(option)
            XCTAssertEqual(normalCalls, 1)
            XCTAssertEqual(optionCalls, 1)
            XCTAssertFalse(MediaKeyInterceptor.dispatchKey(
                keyCode: keyCode, option: true, shift: true, command: false,
                brightnessSupported: false,
                optionAction: { XCTFail("fine adjustment is not an option action"); return true },
                normalAction: { XCTFail("unsupported normal adjustment") }))
        }
    }

    func testQueuedAbsoluteAndRelativeWritesRecheckDisabledLifecycleBeforeDispatch() async {
        for invalidate in [false, true] {
            let client = FakeBrightnessClient()
            client.targetID = 7
            client.values[7] = 0.4
            var enabled = true
            var events = 0
            let manager = BrightnessManager(
                client: client, displayUUID: { "display-\($0)" }, eventSink: { _, _ in events += 1 },
                observeTopology: false, controlEnabled: { enabled })
            await settle()
            manager.setAbsolute(value: 0.8)
            manager.setRelative(delta: 0.1)
            enabled = false
            if invalidate { manager.invalidateTopology() }
            await settle()
            XCTAssertTrue(client.sets.isEmpty)
            XCTAssertTrue(client.adjustments.isEmpty)
            XCTAssertEqual(client.values[7], 0.4)
            XCTAssertEqual(events, 0)
            enabled = true
            if invalidate {
                manager.invalidateTopology()
                await settle()
            }
            manager.setRelative(delta: 0.2)
            await settle()
            XCTAssertEqual(client.adjustments.count, 1)
            XCTAssertEqual(client.adjustments.first?.0 ?? -1, 0.2, accuracy: 0.0001)
        }
    }

    func testQueuedWritesCannotFollowAReplacementTarget() async {
        let client = FakeBrightnessClient()
        client.targetID = 7
        client.values[7] = 0.4
        client.values[8] = 0.2
        let manager = makeManager(client: client) { _, _ in }
        await settle()
        manager.setAbsolute(value: 0.8)
        manager.setRelative(delta: 0.1)
        client.targetID = 8
        manager.invalidateTopology()
        await settle()
        XCTAssertTrue(client.sets.isEmpty)
        XCTAssertTrue(client.adjustments.isEmpty)
        manager.setRelative(delta: 0.2)
        await settle()
        XCTAssertEqual(client.adjustments.count, 1)
        XCTAssertEqual(client.adjustments.first?.1, 8)
        XCTAssertEqual(client.values[7], 0.4)
        XCTAssertEqual(client.values[8] ?? -1, 0.4, accuracy: 0.0001)
        manager.setAbsolute(value: 0.8)
        await settle()
        XCTAssertEqual(client.sets.count, 1)
        XCTAssertEqual(client.sets.first?.1, 8)
        XCTAssertEqual(client.values[8], 0.8)
    }

    func testDisabledLifecycleSkipsWriteBasedDiscoveryAndRefreshesOnEnable() async {
        let client = FakeBrightnessClient()
        client.targetID = 7
        client.values[7] = 0.4
        var enabled = false
        let manager = BrightnessManager(
            client: client, displayUUID: { "display-\($0)" }, eventSink: { _, _ in },
            observeTopology: false, controlEnabled: { enabled })
        await settle()
        manager.invalidateTopology()
        await settle()
        XCTAssertEqual(client.discoveryCalls, 0)
        XCTAssertFalse(manager.canAdjustBrightness)
        enabled = true
        manager.invalidateTopology()
        await settle()
        XCTAssertEqual(client.discoveryCalls, 1)
        XCTAssertTrue(manager.canAdjustBrightness)
        enabled = false
        manager.invalidateTopology()
        manager.setRelative(delta: 0.1)
        manager.setAbsolute(value: 0.8)
        await settle()
        XCTAssertEqual(client.discoveryCalls, 1)
        XCTAssertTrue(client.adjustments.isEmpty)
        XCTAssertTrue(client.sets.isEmpty)
        XCTAssertFalse(manager.canAdjustBrightness)
    }

    func testRelativeOperationAndHUDUseSameVerifiedDisplay() async {
        let client = FakeBrightnessClient()
        client.targetID = 7
        client.values[7] = 0.4
        client.authoritativeAdjustment = 0.625
        var events: [(Float, String?)] = []
        let manager = makeManager(client: client) { events.append(($0, $1)) }
        await settle()

        XCTAssertTrue(manager.canAdjustBrightness)
        manager.setRelative(delta: 0.1)
        await settle()

        XCTAssertEqual(client.adjustments.count, 1)
        XCTAssertEqual(client.adjustments.first?.1, 7)
        XCTAssertEqual(manager.rawBrightness, 0.625, accuracy: 0.0001)
        XCTAssertEqual(events.first?.1, "display-7")
    }

    func testNoSupportedOutputLeavesNativePathAvailable() async {
        let client = FakeBrightnessClient()
        client.targetID = nil
        let manager = makeManager(client: client) { _, _ in XCTFail("unexpected event") }
        await settle()

        XCTAssertFalse(manager.canAdjustBrightness)
        manager.setRelative(delta: 0.1)
        await settle()
        XCTAssertTrue(client.adjustments.isEmpty)
    }

    func testDisplayRemovalInvalidatesInFlightReply() async {
        let client = FakeBrightnessClient()
        client.targetID = 9
        client.values[9] = 0.4
        client.suspendedAdjustments.insert(9)
        var events: [(Float, String?)] = []
        let manager = makeManager(client: client) { events.append(($0, $1)) }
        await settle()

        manager.setRelative(delta: 0.1)
        await settle()
        XCTAssertEqual(client.adjustments.count, 1)
        client.targetID = nil
        manager.invalidateTopology()
        client.resumeAdjustment(displayID: 9, brightness: 0.5)
        await settle()

        XCTAssertFalse(manager.canAdjustBrightness)
        XCTAssertEqual(manager.rawBrightness, 0.4, accuracy: 0.0001)
        XCTAssertTrue(events.isEmpty)
    }

    func testRapidKeysCoalesceWhileOneOperationIsInFlight() async {
        let client = FakeBrightnessClient()
        client.targetID = 11
        client.values[11] = 0.5
        client.suspendedAdjustments.insert(11)
        let manager = makeManager(client: client) { _, _ in }
        await settle()

        manager.setRelative(delta: 0.0625)
        await settle()
        manager.setRelative(delta: 0.0625)
        manager.setRelative(delta: 0.0625)
        client.resumeAdjustment(displayID: 11, brightness: 0.5625)
        await settle(12)

        XCTAssertEqual(client.adjustments.count, 2)
        XCTAssertEqual(client.adjustments[1].0, 0.125, accuracy: 0.0001)
        XCTAssertEqual(client.adjustments[1].1, 11)
    }

    func testHUDUsesTransportResultInsteadOfRequestedEndpoint() async {
        let client = FakeBrightnessClient()
        client.targetID = 13
        client.values[13] = 0.99
        client.authoritativeAdjustment = 1
        let manager = makeManager(client: client) { _, _ in }
        await settle()

        manager.setRelative(delta: 0.01)
        await settle()
        XCTAssertEqual(manager.rawBrightness, 1, accuracy: 0.0001)
    }

    func testCanceledOldTaskCannotClearNewSuspendedTaskOwnership() async {
        let client = FakeBrightnessClient()
        client.targetID = 21
        client.values[21] = 0.4
        client.values[22] = 0.2
        client.suspendedAdjustments = [21, 22]
        let manager = makeManager(client: client) { _, _ in }
        await settle()

        manager.setRelative(delta: 0.1)
        await settle()
        XCTAssertEqual(client.adjustments.map(\.1), [21])

        client.targetID = 22
        manager.invalidateTopology()
        await settle()
        manager.setRelative(delta: 0.1)
        await settle()
        XCTAssertEqual(client.adjustments.map(\.1), [21, 22])

        client.resumeAdjustment(displayID: 21, brightness: 0.5)
        await settle()
        manager.setRelative(delta: 0.1)
        await settle()
        XCTAssertEqual(client.adjustments.map(\.1), [21, 22])

        client.resumeAdjustment(displayID: 22, brightness: 0.3)
        await settle(12)
        XCTAssertEqual(client.adjustments.map(\.1), [21, 22, 22])
    }

    private func makeManager(
        client: FakeBrightnessClient,
        eventSink: @escaping (Float, String?) -> Void
    ) -> BrightnessManager {
        BrightnessManager(
            client: client,
            displayUUID: { "display-\($0)" },
            eventSink: eventSink,
            observeTopology: false)
    }

    private func settle(_ iterations: Int = 6) async {
        for _ in 0..<iterations { await Task.yield() }
    }
}
