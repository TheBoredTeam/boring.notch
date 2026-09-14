import CoreAudio
import XCTest
@testable import boringNotch

private final class FakeVolumeHardware: VolumeHardwareIO {
    var defaultDevice: AudioObjectID = 1
    var elements: [AudioObjectID: [UInt32]] = [:]
    var access: [AudioObjectID: [UInt32: VolumePropertyAccess]] = [:]
    var muteAccessByDevice: [AudioObjectID: VolumePropertyAccess] = [:]
    var volumes: [AudioObjectID: [UInt32: Float32]] = [:]
    var mute: [AudioObjectID: Bool] = [:]
    var failingVolumeWrites: Set<UInt32> = []
    var volumeWrites: [(AudioObjectID, UInt32, Float32)] = []
    var muteWrites: [(AudioObjectID, Bool)] = []

    func defaultOutputDeviceID() -> AudioObjectID { defaultDevice }
    func outputVolumeElements(deviceID: AudioObjectID) -> [UInt32] { elements[deviceID] ?? [] }
    func volumeAccess(deviceID: AudioObjectID, element: UInt32) -> VolumePropertyAccess {
        access[deviceID]?[element] ?? .init(readable: false, settable: false)
    }
    func muteAccess(deviceID: AudioObjectID) -> VolumePropertyAccess {
        muteAccessByDevice[deviceID] ?? .init(readable: false, settable: false)
    }
    func readVolume(deviceID: AudioObjectID, element: UInt32) -> Float32? {
        volumes[deviceID]?[element]
    }
    func writeVolume(deviceID: AudioObjectID, element: UInt32, value: Float32) -> Bool {
        volumeWrites.append((deviceID, element, value))
        guard !failingVolumeWrites.contains(element) else { return false }
        volumes[deviceID, default: [:]][element] = value
        return true
    }
    func readMute(deviceID: AudioObjectID) -> Bool? { mute[deviceID] }
    func writeMute(deviceID: AudioObjectID, muted: Bool) -> Bool {
        muteWrites.append((deviceID, muted))
        mute[deviceID] = muted
        return true
    }

    func configureMaster(
        device: AudioObjectID, volume: Float32, settable: Bool = true,
        muteValue: Bool? = false, muteSettable: Bool = true
    ) {
        elements[device] = [kAudioObjectPropertyElementMain]
        access[device] = [
            kAudioObjectPropertyElementMain: .init(readable: true, settable: settable)
        ]
        volumes[device] = [kAudioObjectPropertyElementMain: volume]
        muteAccessByDevice[device] = .init(
            readable: muteValue != nil, settable: muteValue != nil && muteSettable)
        mute[device] = muteValue
    }
}

final class VolumeRouteTests: XCTestCase {
    func testRapidKeysCoalesceToLatestIntent() {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.25)
        let engine = VolumeRouteEngine(io: io)
        let initial = engine.switchToDefaultRoute()

        XCTAssertTrue(engine.queueVolume(0.5, expectedGeneration: initial.generation, sequence: 1))
        XCTAssertTrue(engine.queueVolume(0.75, expectedGeneration: initial.generation, sequence: 1))
        let result = engine.flushVolume(expectedGeneration: initial.generation)

        XCTAssertEqual(io.volumeWrites.count, 1)
        XCTAssertEqual(io.volumeWrites.first?.2 ?? -1, 0.75, accuracy: 0.0001)
        XCTAssertEqual(result?.volume ?? -1, 0.75, accuracy: 0.0001)
    }

    func testFailedWriteRetiresIntentAndReconcilesHardware() {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.4)
        io.failingVolumeWrites.insert(kAudioObjectPropertyElementMain)
        let engine = VolumeRouteEngine(io: io)
        let initial = engine.switchToDefaultRoute()

        XCTAssertTrue(engine.queueVolume(0.8, expectedGeneration: initial.generation, sequence: 1))
        let result = engine.flushVolume(expectedGeneration: initial.generation)
        let laterEvent = engine.handlePropertyEvent(
            deviceID: 1, expectedGeneration: initial.generation)

        XCTAssertEqual(result?.volume ?? -1, 0.4, accuracy: 0.0001)
        XCTAssertEqual(laterEvent?.volume ?? -1, 0.4, accuracy: 0.0001)
    }

    func testMuteReconciliationCannotOverwritePendingVolumeIntent() {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.3, muteValue: true)
        let engine = VolumeRouteEngine(io: io)
        let initial = engine.switchToDefaultRoute()

        XCTAssertTrue(engine.queueVolume(0.6, expectedGeneration: initial.generation, sequence: 1))
        let muteResult = engine.setMute(false, expectedGeneration: initial.generation, sequence: 1)

        XCTAssertNil(muteResult?.volume)
        XCTAssertEqual(muteResult?.muted, false)
        let volumeResult = engine.flushVolume(expectedGeneration: initial.generation)
        XCTAssertEqual(volumeResult?.volume ?? -1, 0.6, accuracy: 0.0001)
    }

    func testNewerMuteRetiresOlderPendingVolumeWrite() {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.4, muteValue: false)
        let engine = VolumeRouteEngine(io: io)
        let initial = engine.switchToDefaultRoute()

        XCTAssertTrue(engine.queueVolume(
            0.6, expectedGeneration: initial.generation, sequence: 1))
        let muteResult = engine.setMute(
            true, expectedGeneration: initial.generation, sequence: 2)

        XCTAssertEqual(muteResult?.muted, true)
        XCTAssertNil(engine.flushVolume(expectedGeneration: initial.generation))
        XCTAssertTrue(io.volumeWrites.isEmpty)
    }

    func testMuteAndPendingWritesCannotCrossRouteGeneration() {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.3, muteValue: true)
        io.configureMaster(device: 2, volume: 0.9, muteValue: false)
        let engine = VolumeRouteEngine(io: io)
        let first = engine.switchToDefaultRoute()
        XCTAssertTrue(engine.queueVolume(0.6, expectedGeneration: first.generation, sequence: 1))

        io.defaultDevice = 2
        let second = engine.switchToDefaultRoute()

        XCTAssertNil(engine.flushVolume(expectedGeneration: first.generation))
        XCTAssertNil(engine.setMute(false, expectedGeneration: first.generation, sequence: 1))
        XCTAssertNil(engine.handlePropertyEvent(deviceID: 1, expectedGeneration: first.generation))
        XCTAssertEqual(second.volume ?? -1, 0.9, accuracy: 0.0001)
        XCTAssertEqual(second.muted, false)
        XCTAssertTrue(io.volumeWrites.isEmpty)
        XCTAssertTrue(io.muteWrites.isEmpty)
    }

    func testStereoWritePreservesBalanceAndIgnoresReadOnlyMaster() {
        let io = FakeVolumeHardware()
        io.elements[1] = [kAudioObjectPropertyElementMain, 1, 2]
        io.access[1] = [
            kAudioObjectPropertyElementMain: .init(readable: true, settable: false),
            1: .init(readable: true, settable: true),
            2: .init(readable: true, settable: true),
        ]
        io.volumes[1] = [kAudioObjectPropertyElementMain: 0.95, 1: 0.4, 2: 0.6]
        let engine = VolumeRouteEngine(io: io)
        let initial = engine.switchToDefaultRoute()

        XCTAssertEqual(initial.volume ?? -1, 0.6, accuracy: 0.0001)
        XCTAssertTrue(engine.queueVolume(0.7, expectedGeneration: initial.generation, sequence: 1))
        _ = engine.flushVolume(expectedGeneration: initial.generation)

        XCTAssertEqual(io.volumes[1]?[1] ?? -1, 0.4667, accuracy: 0.0001)
        XCTAssertEqual(io.volumes[1]?[2] ?? -1, 0.7, accuracy: 0.0001)
        let ratio = (io.volumes[1]?[1] ?? 0) / (io.volumes[1]?[2] ?? 1)
        XCTAssertEqual(ratio, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertFalse(io.volumeWrites.contains { $0.1 == kAudioObjectPropertyElementMain })
    }

    func testChannelGainPreservesSilentChannelAtEndpoints() {
        let io = FakeVolumeHardware()
        io.elements[1] = [1, 2]
        io.access[1] = [
            1: .init(readable: true, settable: true),
            2: .init(readable: true, settable: true),
        ]
        io.volumes[1] = [1: 0, 2: 0.6]
        let engine = VolumeRouteEngine(io: io)
        let initial = engine.switchToDefaultRoute()

        XCTAssertTrue(engine.queueVolume(1, expectedGeneration: initial.generation, sequence: 1))
        _ = engine.flushVolume(expectedGeneration: initial.generation)
        XCTAssertEqual(io.volumes[1]?[1] ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(io.volumes[1]?[2] ?? -1, 1, accuracy: 0.0001)

        XCTAssertTrue(engine.queueVolume(0, expectedGeneration: initial.generation, sequence: 2))
        _ = engine.flushVolume(expectedGeneration: initial.generation)
        XCTAssertEqual(io.volumes[1]?[1] ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(io.volumes[1]?[2] ?? -1, 0, accuracy: 0.0001)
    }

    func testChannelSoftwareMuteRestoresRouteLocalBalance() {
        let io = FakeVolumeHardware()
        io.elements[1] = [1, 2]
        io.access[1] = [
            1: .init(readable: true, settable: true),
            2: .init(readable: true, settable: true),
        ]
        io.volumes[1] = [1: 0, 2: 0.6]
        let engine = VolumeRouteEngine(io: io)
        let initial = engine.switchToDefaultRoute()

        let muted = engine.setMute(true, expectedGeneration: initial.generation, sequence: 1)
        XCTAssertEqual(muted?.muted, true)
        XCTAssertEqual(io.volumes[1]?[1] ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(io.volumes[1]?[2] ?? -1, 0, accuracy: 0.0001)

        let restored = engine.setMute(false, expectedGeneration: initial.generation, sequence: 2)
        XCTAssertEqual(restored?.muted, false)
        XCTAssertEqual(io.volumes[1]?[1] ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(io.volumes[1]?[2] ?? -1, 0.6, accuracy: 0.0001)
    }

    func testReadOnlyDACObservesWithoutClaimingControl() {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.55, settable: false, muteValue: nil)
        let engine = VolumeRouteEngine(io: io)
        let initial = engine.switchToDefaultRoute()

        XCTAssertEqual(initial.volume ?? -1, 0.55, accuracy: 0.0001)
        XCTAssertFalse(initial.canAdjustVolume)
        XCTAssertFalse(initial.canToggleMute)
        XCTAssertFalse(engine.queueVolume(0.8, expectedGeneration: initial.generation, sequence: 1))
    }

    func testInitialSubscriptionIsQuietAndExternalChangeIsMarkedOnceStateIsArmed() {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.2)
        let engine = VolumeRouteEngine(io: io)
        let initial = engine.switchToDefaultRoute()
        XCTAssertFalse(initial.isExternalChange)

        io.volumes[1]?[kAudioObjectPropertyElementMain] = 0.45
        let external = engine.handlePropertyEvent(
            deviceID: 1, expectedGeneration: initial.generation)
        XCTAssertTrue(external?.isExternalChange == true)
        XCTAssertEqual(external?.volume ?? -1, 0.45, accuracy: 0.0001)
    }
}

private final class DeferredVolumeDelivery {
    private let lock = NSLock()
    private var actions: [() -> Void] = []

    func enqueue(_ action: @escaping () -> Void) {
        lock.lock()
        actions.append(action)
        lock.unlock()
    }

    func pop() -> (() -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        guard !actions.isEmpty else { return nil }
        return actions.removeFirst()
    }
}

@MainActor
final class VolumeManagerDeliveryTests: XCTestCase {
    func testOlderVolumeDeliveryCannotOverwriteNewerIntent() async {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.5, muteValue: nil)
        let (manager, delivery) = makeManager(io: io)
        await applyNext(delivery)

        manager.increase()
        let first = await nextAction(delivery)
        manager.increase()
        let second = await nextAction(delivery)

        first()
        await settleMainActor()
        XCTAssertEqual(manager.rawVolume, 0.625, accuracy: 0.0001)
        second()
        await settleMainActor()
        XCTAssertEqual(manager.rawVolume, 0.625, accuracy: 0.0001)
    }

    func testOlderMuteDeliveryCannotOverwriteNewerIntent() async {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.4, muteValue: false)
        let (manager, delivery) = makeManager(io: io)
        await applyNext(delivery)

        manager.toggleMuteAction()
        let muted = await nextAction(delivery)
        manager.toggleMuteAction()
        let unmuted = await nextAction(delivery)

        muted()
        await settleMainActor()
        XCTAssertFalse(manager.isMuted)
        unmuted()
        await settleMainActor()
        XCTAssertFalse(manager.isMuted)
        XCTAssertEqual(manager.rawVolume, 0.4, accuracy: 0.0001)
    }

    func testFailedSoftwareMuteReconcilesToAudibleHardware() async {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.4, muteValue: nil)
        io.failingVolumeWrites.insert(kAudioObjectPropertyElementMain)
        let (manager, delivery) = makeManager(io: io)
        await applyNext(delivery)

        manager.toggleMuteAction()
        XCTAssertTrue(manager.isMuted)
        await applyNext(delivery)

        XCTAssertFalse(manager.isMuted)
        XCTAssertEqual(manager.rawVolume, 0.4, accuracy: 0.0001)
    }

    func testExternalVolumeRestoreClearsSoftwareMute() async {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.4, muteValue: nil)
        let (manager, delivery) = makeManager(io: io)
        await applyNext(delivery)

        manager.toggleMuteAction()
        await applyNext(delivery)
        XCTAssertTrue(manager.isMuted)

        io.volumes[1]?[kAudioObjectPropertyElementMain] = 0.55
        manager.processRoutePropertyChange(deviceID: 1, generation: 1)
        await applyNext(delivery)
        XCTAssertFalse(manager.isMuted)
        XCTAssertEqual(manager.rawVolume, 0.55, accuracy: 0.0001)
    }

    func testReadOnlyHardwareMuteUsesSoftwareMuteAuthority() async {
        let io = FakeVolumeHardware()
        io.configureMaster(
            device: 1, volume: 0.4, muteValue: false, muteSettable: false)
        let (manager, delivery) = makeManager(io: io)
        await applyNext(delivery)

        manager.toggleMuteAction()
        await applyNext(delivery)

        XCTAssertTrue(manager.isMuted)
        XCTAssertEqual(manager.rawVolume, 0, accuracy: 0.0001)
        XCTAssertEqual(io.muteWrites.count, 0)
    }

    func testNewZeroAndUnavailableRoutesResetRestoreAndPresentationState() async {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.9, muteValue: nil)
        io.configureMaster(device: 2, volume: 0, muteValue: nil)
        let (manager, delivery) = makeManager(io: io)
        await applyNext(delivery)

        io.defaultDevice = 2
        manager.refreshRoute()
        await applyNext(delivery)
        XCTAssertEqual(manager.rawVolume, 0, accuracy: 0.0001)
        XCTAssertTrue(manager.isMuted)

        manager.toggleMuteAction()
        await applyNext(delivery)
        XCTAssertEqual(manager.rawVolume, 0.2, accuracy: 0.0001)
        XCTAssertFalse(manager.isMuted)

        io.defaultDevice = 3
        manager.refreshRoute()
        await applyNext(delivery)
        XCTAssertEqual(manager.rawVolume, 0, accuracy: 0.0001)
        XCTAssertFalse(manager.isMuted)
        XCTAssertFalse(manager.canAdjustVolume)
        XCTAssertFalse(manager.canToggleMute)
    }

    private func makeManager(
        io: FakeVolumeHardware
    ) -> (VolumeManager, DeferredVolumeDelivery) {
        let delivery = DeferredVolumeDelivery()
        let manager = VolumeManager(
            io: io, audioQueue: DispatchQueue(label: "VolumeManagerDeliveryTests"),
            writeFlushInterval: 0,
            mainDelivery: { delivery.enqueue($0) })
        manager.refreshRoute()
        return (manager, delivery)
    }

    private func applyNext(_ delivery: DeferredVolumeDelivery) async {
        let action = await nextAction(delivery)
        action()
        await settleMainActor()
    }

    private func settleMainActor() async {
        for _ in 0..<4 { await Task.yield() }
    }

    private func nextAction(_ delivery: DeferredVolumeDelivery) async -> () -> Void {
        for _ in 0..<200 {
            if let action = delivery.pop() { return action }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for deferred volume delivery")
        return {}
    }
}
