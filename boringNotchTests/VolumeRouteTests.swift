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

        XCTAssertTrue(engine.queueVolume(0.5, expectedGeneration: initial.generation))
        XCTAssertTrue(engine.queueVolume(0.75, expectedGeneration: initial.generation))
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

        XCTAssertTrue(engine.queueVolume(0.8, expectedGeneration: initial.generation))
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

        XCTAssertTrue(engine.queueVolume(0.6, expectedGeneration: initial.generation))
        let muteResult = engine.setMute(false, expectedGeneration: initial.generation)

        XCTAssertNil(muteResult?.volume)
        XCTAssertEqual(muteResult?.muted, false)
        let volumeResult = engine.flushVolume(expectedGeneration: initial.generation)
        XCTAssertEqual(volumeResult?.volume ?? -1, 0.6, accuracy: 0.0001)
    }

    func testMuteAndPendingWritesCannotCrossRouteGeneration() {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.3, muteValue: true)
        io.configureMaster(device: 2, volume: 0.9, muteValue: false)
        let engine = VolumeRouteEngine(io: io)
        let first = engine.switchToDefaultRoute()
        XCTAssertTrue(engine.queueVolume(0.6, expectedGeneration: first.generation))

        io.defaultDevice = 2
        let second = engine.switchToDefaultRoute()

        XCTAssertNil(engine.flushVolume(expectedGeneration: first.generation))
        XCTAssertNil(engine.setMute(false, expectedGeneration: first.generation))
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

        XCTAssertEqual(initial.volume ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertTrue(engine.queueVolume(0.7, expectedGeneration: initial.generation))
        _ = engine.flushVolume(expectedGeneration: initial.generation)

        XCTAssertEqual(io.volumes[1]?[1] ?? -1, 0.6, accuracy: 0.0001)
        XCTAssertEqual(io.volumes[1]?[2] ?? -1, 0.8, accuracy: 0.0001)
        let balance = (io.volumes[1]?[2] ?? 0) - (io.volumes[1]?[1] ?? 0)
        XCTAssertEqual(balance, 0.2, accuracy: 0.0001)
        XCTAssertFalse(io.volumeWrites.contains { $0.1 == kAudioObjectPropertyElementMain })
    }

    func testReadOnlyDACObservesWithoutClaimingControl() {
        let io = FakeVolumeHardware()
        io.configureMaster(device: 1, volume: 0.55, settable: false, muteValue: nil)
        let engine = VolumeRouteEngine(io: io)
        let initial = engine.switchToDefaultRoute()

        XCTAssertEqual(initial.volume ?? -1, 0.55, accuracy: 0.0001)
        XCTAssertFalse(initial.canAdjustVolume)
        XCTAssertFalse(initial.canToggleMute)
        XCTAssertFalse(engine.queueVolume(0.8, expectedGeneration: initial.generation))
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
