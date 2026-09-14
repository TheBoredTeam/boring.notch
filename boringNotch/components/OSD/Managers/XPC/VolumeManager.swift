import AppKit
import Combine
import CoreAudio
import Foundation

struct VolumePropertyAccess: Equatable {
    let readable: Bool
    let settable: Bool
}

protocol VolumeHardwareIO {
    func defaultOutputDeviceID() -> AudioObjectID
    func outputVolumeElements(deviceID: AudioObjectID) -> [UInt32]
    func volumeAccess(deviceID: AudioObjectID, element: UInt32) -> VolumePropertyAccess
    func muteAccess(deviceID: AudioObjectID) -> VolumePropertyAccess
    func readVolume(deviceID: AudioObjectID, element: UInt32) -> Float32?
    func writeVolume(deviceID: AudioObjectID, element: UInt32, value: Float32) -> Bool
    func readMute(deviceID: AudioObjectID) -> Bool?
    func writeMute(deviceID: AudioObjectID, muted: Bool) -> Bool
}

private struct CoreAudioVolumeIO: VolumeHardwareIO {
    func defaultOutputDeviceID() -> AudioObjectID {
        var deviceID = kAudioObjectUnknown
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr
        else { return kAudioObjectUnknown }
        return deviceID
    }

    func outputVolumeElements(deviceID: AudioObjectID) -> [UInt32] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var channelCount = 0
        if AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
           size >= UInt32(MemoryLayout<AudioBufferList>.size)
        {
            let storage = UnsafeMutableRawPointer.allocate(
                byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { storage.deallocate() }
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, storage) == noErr {
                let buffers = UnsafeMutableAudioBufferListPointer(
                    storage.assumingMemoryBound(to: AudioBufferList.self))
                channelCount = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
            }
        }
        return [kAudioObjectPropertyElementMain]
            + (channelCount > 0 ? Array(1...UInt32(channelCount)) : [])
    }

    func volumeAccess(deviceID: AudioObjectID, element: UInt32) -> VolumePropertyAccess {
        propertyAccess(
            deviceID: deviceID, selector: kAudioDevicePropertyVolumeScalar, element: element,
            expectedSize: UInt32(MemoryLayout<Float32>.size))
    }

    func muteAccess(deviceID: AudioObjectID) -> VolumePropertyAccess {
        propertyAccess(
            deviceID: deviceID, selector: kAudioDevicePropertyMute,
            element: kAudioObjectPropertyElementMain,
            expectedSize: UInt32(MemoryLayout<UInt32>.size))
    }

    func readVolume(deviceID: AudioObjectID, element: UInt32) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr
        else { return nil }
        return value
    }

    func writeVolume(deviceID: AudioObjectID, element: UInt32, value: Float32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        var value = value
        return AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    func readMute(deviceID: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr
        else { return nil }
        return value != 0
    }

    func writeMute(deviceID: AudioObjectID, muted: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private func propertyAccess(
        deviceID: AudioObjectID, selector: AudioObjectPropertySelector, element: UInt32,
        expectedSize: UInt32
    ) -> VolumePropertyAccess {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        guard AudioObjectHasProperty(deviceID, &address) else {
            return VolumePropertyAccess(readable: false, settable: false)
        }
        var size: UInt32 = 0
        let readable = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
            && size == expectedSize
        var settable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(deviceID, &address, &settable)
        return VolumePropertyAccess(
            readable: readable, settable: status == noErr && settable.boolValue)
    }
}

struct VolumeRouteObservation: Equatable {
    let generation: UInt64
    let deviceID: AudioObjectID
    let volume: Float32?
    let muted: Bool?
    let canAdjustVolume: Bool
    let canToggleMute: Bool
    let isInitialSync: Bool
    let isExternalChange: Bool
}

/// Synchronous route state machine. The manager serializes calls on its audio
/// queue; tests inject fake CoreAudio reads, writes and listener events.
final class VolumeRouteEngine {
    private struct Route {
        let generation: UInt64
        let deviceID: AudioObjectID
        let readableElements: [UInt32]
        let writableElements: [UInt32]
        let muteReadable: Bool
        let muteSettable: Bool
    }
    private struct Intent { let generation: UInt64; let target: Float32 }

    private let io: any VolumeHardwareIO
    private(set) var generation: UInt64 = 0
    private var route: Route?
    private var pendingVolume: Intent?
    private var pendingMute: (generation: UInt64, muted: Bool)?
    private var didSynchronize = false

    init(io: any VolumeHardwareIO) { self.io = io }

    var deviceID: AudioObjectID { route?.deviceID ?? kAudioObjectUnknown }
    var listenedVolumeElements: [UInt32] { route?.readableElements ?? [] }
    var listensForMute: Bool { route?.muteReadable == true }

    func switchToDefaultRoute() -> VolumeRouteObservation {
        generation &+= 1
        pendingVolume = nil
        pendingMute = nil
        didSynchronize = false
        let deviceID = io.defaultOutputDeviceID()
        let elements = deviceID == kAudioObjectUnknown ? [] : io.outputVolumeElements(deviceID: deviceID)
        let controls = elements.map { ($0, io.volumeAccess(deviceID: deviceID, element: $0)) }
        let master = controls.first { $0.0 == kAudioObjectPropertyElementMain }
        let writable: [UInt32]
        if let master, master.1.readable && master.1.settable {
            writable = [master.0]
        } else {
            writable = controls.filter {
                $0.0 != kAudioObjectPropertyElementMain && $0.1.readable && $0.1.settable
            }.map(\.0)
        }
        let readable: [UInt32]
        if !writable.isEmpty {
            readable = writable
        } else if let master, master.1.readable {
            readable = [master.0]
        } else {
            readable = controls.filter {
                $0.0 != kAudioObjectPropertyElementMain && $0.1.readable
            }.map(\.0)
        }
        let mute = deviceID == kAudioObjectUnknown
            ? VolumePropertyAccess(readable: false, settable: false)
            : io.muteAccess(deviceID: deviceID)
        route = Route(
            generation: generation, deviceID: deviceID, readableElements: readable,
            writableElements: writable, muteReadable: mute.readable,
            muteSettable: mute.readable && mute.settable)
        return observation(expectedGeneration: generation, external: false, initial: true)
    }

    func queueVolume(_ target: Float32, expectedGeneration: UInt64) -> Bool {
        guard let route, route.generation == expectedGeneration, !route.writableElements.isEmpty
        else { return false }
        pendingVolume = Intent(generation: expectedGeneration, target: max(0, min(1, target)))
        return true
    }

    func flushVolume(expectedGeneration: UInt64) -> VolumeRouteObservation? {
        guard let route, route.generation == expectedGeneration,
              let intent = pendingVolume, intent.generation == expectedGeneration
        else { return nil }
        pendingVolume = nil
        let samples = route.writableElements.compactMap { element in
            io.readVolume(deviceID: route.deviceID, element: element).map { (element, $0) }
        }
        guard samples.count == route.writableElements.count else {
            return observation(expectedGeneration: expectedGeneration, external: false)
        }
        if route.writableElements == [kAudioObjectPropertyElementMain] {
            _ = io.writeVolume(
                deviceID: route.deviceID, element: kAudioObjectPropertyElementMain,
                value: intent.target)
        } else {
            let average = samples.reduce(Float32(0)) { $0 + $1.1 } / Float32(samples.count)
            let delta = intent.target - average
            for (element, current) in samples {
                _ = io.writeVolume(
                    deviceID: route.deviceID, element: element,
                    value: max(0, min(1, current + delta)))
            }
        }
        return observation(expectedGeneration: expectedGeneration, external: false)
    }

    func setMute(_ muted: Bool, expectedGeneration: UInt64) -> VolumeRouteObservation? {
        guard let route, route.generation == expectedGeneration, route.muteSettable else { return nil }
        pendingMute = (expectedGeneration, muted)
        _ = io.writeMute(deviceID: route.deviceID, muted: muted)
        pendingMute = nil
        return observation(expectedGeneration: expectedGeneration, external: false)
    }

    func handlePropertyEvent(
        deviceID: AudioObjectID, expectedGeneration: UInt64
    ) -> VolumeRouteObservation? {
        guard let route, route.deviceID == deviceID, route.generation == expectedGeneration else {
            return nil
        }
        return observation(expectedGeneration: expectedGeneration, external: true)
    }

    private func observation(
        expectedGeneration: UInt64, external: Bool, initial: Bool = false
    ) -> VolumeRouteObservation {
        guard let route, route.generation == expectedGeneration else {
            return VolumeRouteObservation(
                generation: expectedGeneration, deviceID: kAudioObjectUnknown, volume: nil,
                muted: nil, canAdjustVolume: false, canToggleMute: false,
                isInitialSync: initial, isExternalChange: false)
        }
        let values = route.readableElements.compactMap {
            io.readVolume(deviceID: route.deviceID, element: $0)
        }
        let volume = values.isEmpty ? nil : values.reduce(0, +) / Float32(values.count)
        let muted = route.muteReadable ? io.readMute(deviceID: route.deviceID) : nil
        let suppressVolume = pendingVolume?.generation == expectedGeneration
        let suppressMute = pendingMute?.generation == expectedGeneration
        let wasInitial = initial || !didSynchronize
        didSynchronize = true
        return VolumeRouteObservation(
            generation: expectedGeneration, deviceID: route.deviceID,
            volume: suppressVolume ? nil : volume, muted: suppressMute ? nil : muted,
            canAdjustVolume: !route.writableElements.isEmpty,
            canToggleMute: route.muteSettable, isInitialSync: wasInitial,
            isExternalChange: external && !wasInitial)
    }
}

final class VolumeManager: NSObject, ObservableObject {
    static let shared = VolumeManager()

    @Published private(set) var rawVolume: Float = 0
    @Published private(set) var isMuted = false
    @Published private(set) var lastChangeAt: Date = .distantPast
    @Published private(set) var canAdjustVolume = false
    @Published private(set) var canToggleMute = false

    let visibleDuration: TimeInterval = 1.2
    private let step: Float32 = 1.0 / 16.0
    private var previousVolumeBeforeMute: Float32 = 0.2
    private var softwareMuted = false
    private var activeGeneration: UInt64 = 0
    private let audioQueue = DispatchQueue(
        label: "com.boringnotch.osd.volume", qos: .userInitiated)
    private let engine = VolumeRouteEngine(io: CoreAudioVolumeIO())
    private var pendingWriteGeneration: UInt64?
    private var writeFlushScheduled = false
    private let writeFlushInterval: TimeInterval = 1.0 / 15.0

    private struct ListenerRegistration {
        let deviceID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var listeners: [ListenerRegistration] = []

    private override init() {
        super.init()
        installDeviceChangeListener()
        audioQueue.async { [self] in rebuildRouteLocked() }
    }

    var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

    @MainActor func increase(stepDivisor: Float = 1) {
        let divisor = Float32(max(stepDivisor, 0.25))
        commit(target: max(0, min(1, rawVolume + step / divisor)))
    }

    @MainActor func decrease(stepDivisor: Float = 1) {
        let divisor = Float32(max(stepDivisor, 0.25))
        commit(target: max(0, min(1, rawVolume - step / divisor)))
    }

    @MainActor func toggleMuteAction() {
        guard canToggleMute || canAdjustVolume else { return }
        let generation = activeGeneration
        let willMute = !isMuted
        let restored = rawVolume > 0.001 ? rawVolume : previousVolumeBeforeMute
        if canToggleMute {
            enqueueMute(willMute, generation: generation)
        } else if willMute {
            if rawVolume > 0.001 { previousVolumeBeforeMute = rawVolume }
            softwareMuted = true
            requestVolumeWrite(0, generation: generation)
        } else {
            softwareMuted = false
            requestVolumeWrite(previousVolumeBeforeMute, generation: generation)
        }
        publish(
            volume: canToggleMute ? rawVolume : (willMute ? 0 : restored),
            muted: willMute, touchDate: true)
        let displayedVolume = canToggleMute ? rawVolume : restored
        NotchUIEventBus.events.send(
            .sneakPeek(
                type: .volume, value: willMute ? 0 : CGFloat(displayedVolume),
                provider: .builtin))
    }

    @MainActor func setAbsolute(_ value: Float32) {
        commit(target: max(0, min(1, value)))
    }

    @MainActor private func commit(target: Float32) {
        guard canAdjustVolume else { return }
        let generation = activeGeneration
        var muteIntent: Bool?
        if isMuted && target > 0 {
            softwareMuted = false
            if canToggleMute { muteIntent = false }
        }
        if target == 0 && !isMuted {
            if rawVolume > 0.001 { previousVolumeBeforeMute = rawVolume }
            if canToggleMute {
                muteIntent = true
            } else {
                softwareMuted = true
            }
        }
        publish(volume: target, muted: target == 0, touchDate: true)
        requestVolumeWrite(target, generation: generation)
        // Queue volume intent first so synchronous mute reconciliation sees
        // it and cannot overwrite the optimistic key result with an old level.
        if let muteIntent { enqueueMute(muteIntent, generation: generation) }
        NotchUIEventBus.events.send(
            .sneakPeek(type: .volume, value: CGFloat(target), provider: .builtin))
    }

    private func requestVolumeWrite(_ value: Float32, generation: UInt64) {
        audioQueue.async { [self] in
            guard engine.queueVolume(value, expectedGeneration: generation) else { return }
            pendingWriteGeneration = generation
            guard !writeFlushScheduled else { return }
            writeFlushScheduled = true
            audioQueue.asyncAfter(deadline: .now() + writeFlushInterval) { [self] in
                writeFlushScheduled = false
                guard let generation = pendingWriteGeneration else { return }
                pendingWriteGeneration = nil
                if let observation = engine.flushVolume(expectedGeneration: generation) {
                    deliver(observation)
                }
            }
        }
    }

    private func enqueueMute(_ muted: Bool, generation: UInt64) {
        audioQueue.async { [self] in
            if let observation = engine.setMute(muted, expectedGeneration: generation) {
                deliver(observation)
            }
        }
    }

    private func rebuildRouteLocked() {
        removeDeviceListenersLocked()
        pendingWriteGeneration = nil
        let observation = engine.switchToDefaultRoute()
        attachDeviceListenersLocked(generation: observation.generation)
        deliver(observation)
    }

    private func attachDeviceListenersLocked(generation: UInt64) {
        let deviceID = engine.deviceID
        guard deviceID != kAudioObjectUnknown else { return }
        for element in engine.listenedVolumeElements {
            attachListenerLocked(
                deviceID: deviceID, selector: kAudioDevicePropertyVolumeScalar,
                element: element, generation: generation)
        }
        if engine.listensForMute {
            attachListenerLocked(
                deviceID: deviceID, selector: kAudioDevicePropertyMute,
                element: kAudioObjectPropertyElementMain, generation: generation)
        }
    }

    private func attachListenerLocked(
        deviceID: AudioObjectID, selector: AudioObjectPropertySelector, element: UInt32,
        generation: UInt64
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self,
                  let observation = self.engine.handlePropertyEvent(
                    deviceID: deviceID, expectedGeneration: generation)
            else { return }
            self.deliver(observation)
        }
        guard AudioObjectAddPropertyListenerBlock(deviceID, &address, audioQueue, block) == noErr
        else { return }
        listeners.append(
            ListenerRegistration(deviceID: deviceID, address: address, block: block))
    }

    private func removeDeviceListenersLocked() {
        for listener in listeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(
                listener.deviceID, &address, audioQueue, listener.block)
        }
        listeners.removeAll()
    }

    private func installDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, audioQueue
        ) { [weak self] _, _ in self?.rebuildRouteLocked() }
    }

    private func deliver(_ observation: VolumeRouteObservation) {
        DispatchQueue.main.async { [weak self] in self?.apply(observation) }
    }

    @MainActor private func apply(_ observation: VolumeRouteObservation) {
        if observation.isInitialSync {
            guard observation.generation >= activeGeneration else { return }
            activeGeneration = observation.generation
            softwareMuted = false
            if let volume = observation.volume, volume > 0.001 {
                previousVolumeBeforeMute = volume
            }
        } else {
            guard observation.generation == activeGeneration else { return }
        }
        canAdjustVolume = observation.canAdjustVolume
        canToggleMute = observation.canToggleMute
        let effectiveMuted = observation.muted ?? softwareMuted
        let changed = observation.volume.map { abs($0 - rawVolume) > 0.0005 } == true
            || effectiveMuted != isMuted
        if let volume = observation.volume { rawVolume = volume }
        isMuted = effectiveMuted
        guard changed else { return }
        if !observation.isInitialSync { lastChangeAt = Date() }
        // External callbacks and command reconciliation both update the
        // current peek. For a successful exact command `changed` is false,
        // so callback echoes do not create a duplicate presentation.
        if !observation.isInitialSync {
            NotchUIEventBus.events.send(
                .sneakPeek(
                    type: .volume,
                    value: effectiveMuted ? 0 : CGFloat(observation.volume ?? rawVolume),
                    provider: .builtin))
        }
    }

    @MainActor private func publish(volume: Float32, muted: Bool, touchDate: Bool) {
        if touchDate { lastChangeAt = Date() }
        rawVolume = volume
        isMuted = muted
    }
}
