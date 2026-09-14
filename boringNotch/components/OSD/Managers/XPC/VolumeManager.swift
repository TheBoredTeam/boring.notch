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
    let sequence: UInt64
    let deviceID: AudioObjectID
    let volume: Float32?
    let muted: Bool?
    let restoreVolume: Float32
    let canAdjustVolume: Bool
    let canToggleMute: Bool
    let usesHardwareMute: Bool
    let isInitialSync: Bool
    let isExternalChange: Bool
}

/// Synchronous route state machine. The manager serializes calls on its audio
/// queue; tests inject fake CoreAudio reads, writes and listener events.
final class VolumeRouteEngine {
    private enum MuteAuthority {
        case hardware
        case software
        case observedHardware
        case unavailable
    }

    private struct Route {
        let generation: UInt64
        let deviceID: AudioObjectID
        let readableElements: [UInt32]
        let writableElements: [UInt32]
        let muteAuthority: MuteAuthority
        var softwareMuted = false
        var restoreVolume: Float32 = 0.2
        var restoreChannels: [UInt32: Float32]?
    }
    private struct Intent {
        let generation: UInt64
        let sequence: UInt64
        let target: Float32
    }

    private let io: any VolumeHardwareIO
    private(set) var generation: UInt64 = 0
    private var route: Route?
    private var pendingVolume: Intent?
    private var pendingMute: (generation: UInt64, sequence: UInt64, muted: Bool)?
    private var didSynchronize = false
    private var latestSequence: UInt64 = 0

    init(io: any VolumeHardwareIO) { self.io = io }

    var deviceID: AudioObjectID { route?.deviceID ?? kAudioObjectUnknown }
    var listenedVolumeElements: [UInt32] { route?.readableElements ?? [] }
    var listensForMute: Bool {
        switch route?.muteAuthority {
        case .hardware, .observedHardware: true
        default: false
        }
    }

    func switchToDefaultRoute() -> VolumeRouteObservation {
        generation &+= 1
        pendingVolume = nil
        pendingMute = nil
        didSynchronize = false
        latestSequence = 0
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
        let muteAuthority: MuteAuthority
        if mute.readable && mute.settable {
            muteAuthority = .hardware
        } else if !writable.isEmpty {
            muteAuthority = .software
        } else if mute.readable {
            muteAuthority = .observedHardware
        } else {
            muteAuthority = .unavailable
        }
        route = Route(
            generation: generation, deviceID: deviceID, readableElements: readable,
            writableElements: writable, muteAuthority: muteAuthority)
        return observation(
            expectedGeneration: generation, sequence: 0, external: false, initial: true)
    }

    func queueVolume(
        _ target: Float32, expectedGeneration: UInt64, sequence: UInt64
    ) -> Bool {
        guard let route, route.generation == expectedGeneration, !route.writableElements.isEmpty
        else { return false }
        latestSequence = max(latestSequence, sequence)
        pendingVolume = Intent(
            generation: expectedGeneration, sequence: sequence,
            target: max(0, min(1, target)))
        return true
    }

    func flushVolume(expectedGeneration: UInt64) -> VolumeRouteObservation? {
        guard var route, route.generation == expectedGeneration,
              let intent = pendingVolume, intent.generation == expectedGeneration
        else { return nil }
        pendingVolume = nil
        writeVolume(intent.target, route: &route)
        self.route = route
        return observation(
            expectedGeneration: expectedGeneration, sequence: intent.sequence, external: false)
    }

    func setMute(
        _ muted: Bool, expectedGeneration: UInt64, sequence: UInt64
    ) -> VolumeRouteObservation? {
        guard var route, route.generation == expectedGeneration else { return nil }
        latestSequence = max(latestSequence, sequence)
        if let pendingVolume, pendingVolume.sequence < sequence {
            self.pendingVolume = nil
        }
        pendingMute = (expectedGeneration, sequence, muted)
        switch route.muteAuthority {
        case .hardware:
            _ = io.writeMute(deviceID: route.deviceID, muted: muted)
        case .software:
            let target = muted ? Float32(0) : route.restoreVolume
            writeVolume(target, route: &route)
            self.route = route
        case .observedHardware, .unavailable:
            pendingMute = nil
            return nil
        }
        pendingMute = nil
        return observation(
            expectedGeneration: expectedGeneration, sequence: sequence, external: false)
    }

    func handlePropertyEvent(
        deviceID: AudioObjectID, expectedGeneration: UInt64
    ) -> VolumeRouteObservation? {
        guard let route, route.deviceID == deviceID, route.generation == expectedGeneration else {
            return nil
        }
        return observation(
            expectedGeneration: expectedGeneration, sequence: latestSequence, external: true)
    }

    private func observation(
        expectedGeneration: UInt64, sequence: UInt64, external: Bool, initial: Bool = false
    ) -> VolumeRouteObservation {
        guard let route, route.generation == expectedGeneration else {
            return VolumeRouteObservation(
                generation: expectedGeneration, sequence: sequence,
                deviceID: kAudioObjectUnknown, volume: nil, muted: nil, restoreVolume: 0.2,
                canAdjustVolume: false, canToggleMute: false, usesHardwareMute: false,
                isInitialSync: initial, isExternalChange: false)
        }
        let samples = route.readableElements.compactMap { element in
            io.readVolume(deviceID: route.deviceID, element: element).map { (element, $0) }
        }
        let volume = samples.map(\.1).max()
        let suppressVolume = pendingVolume?.generation == expectedGeneration
        var mutableRoute = route
        let muted: Bool?
        switch route.muteAuthority {
        case .hardware:
            muted = io.readMute(deviceID: route.deviceID)
        case .software:
            if let volume {
                mutableRoute.softwareMuted = volume <= 0.0005
                if volume > 0.0005 {
                    mutableRoute.restoreVolume = volume
                    mutableRoute.restoreChannels = Dictionary(
                        uniqueKeysWithValues: samples.map { ($0.0, $0.1) })
                }
            } else {
                mutableRoute.softwareMuted = false
            }
            muted = suppressVolume ? nil : mutableRoute.softwareMuted
        case .observedHardware:
            muted = io.readMute(deviceID: route.deviceID)
        case .unavailable:
            muted = nil
        }
        self.route = mutableRoute
        let suppressMute = pendingMute?.generation == expectedGeneration
        let wasInitial = initial || !didSynchronize
        didSynchronize = true
        return VolumeRouteObservation(
            generation: expectedGeneration, sequence: sequence, deviceID: route.deviceID,
            volume: suppressVolume ? nil : volume, muted: suppressMute ? nil : muted,
            restoreVolume: mutableRoute.restoreVolume,
            canAdjustVolume: !route.writableElements.isEmpty,
            canToggleMute: {
                switch route.muteAuthority {
                case .hardware, .software: true
                case .observedHardware, .unavailable: false
                }
            }(),
            usesHardwareMute: {
                if case .hardware = route.muteAuthority { return true }
                return false
            }(),
            isInitialSync: wasInitial,
            isExternalChange: external && !wasInitial)
    }

    private func writeVolume(_ target: Float32, route: inout Route) {
        let samples = route.writableElements.compactMap { element in
            io.readVolume(deviceID: route.deviceID, element: element).map { (element, $0) }
        }
        guard samples.count == route.writableElements.count else { return }
        let clamped = max(0, min(1, target))
        if route.writableElements == [kAudioObjectPropertyElementMain] {
            if samples[0].1 > 0.0005 {
                route.restoreVolume = samples[0].1
                route.restoreChannels = [samples[0].0: samples[0].1]
            }
            _ = io.writeVolume(
                deviceID: route.deviceID, element: kAudioObjectPropertyElementMain,
                value: clamped)
            return
        }

        let currentPeak = samples.map(\.1).max() ?? 0
        if currentPeak > 0.0005 {
            route.restoreVolume = currentPeak
            route.restoreChannels = Dictionary(
                uniqueKeysWithValues: samples.map { ($0.0, $0.1) })
        }
        let profile = currentPeak > 0.0005
            ? Dictionary(uniqueKeysWithValues: samples.map { ($0.0, $0.1) })
            : route.restoreChannels
        let profilePeak = profile?.values.max() ?? 0
        for element in route.writableElements {
            let value: Float32
            if clamped == 0 {
                value = 0
            } else if let channel = profile?[element], profilePeak > 0.0005 {
                value = clamped * channel / profilePeak
            } else {
                value = clamped
            }
            _ = io.writeVolume(deviceID: route.deviceID, element: element, value: value)
        }
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
    private var activeGeneration: UInt64 = 0
    private var usesHardwareMute = false
    private var latestIntentSequence: UInt64 = 0
    private var nextIntentSequence: UInt64 = 0
    private let audioQueue: DispatchQueue
    private let engine: VolumeRouteEngine
    private let mainDelivery: (@escaping () -> Void) -> Void
    private var pendingWrite: (generation: UInt64, sequence: UInt64)?
    private var writeFlushScheduled = false
    private let writeFlushInterval: TimeInterval

    private struct ListenerRegistration {
        let deviceID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var listeners: [ListenerRegistration] = []

    private override convenience init() {
        self.init(
            io: CoreAudioVolumeIO(),
            audioQueue: DispatchQueue(
                label: "com.boringnotch.osd.volume", qos: .userInitiated),
            writeFlushInterval: 1.0 / 15.0,
            mainDelivery: { action in DispatchQueue.main.async(execute: action) },
            startAutomatically: true)
    }

    init(
        io: any VolumeHardwareIO,
        audioQueue: DispatchQueue,
        writeFlushInterval: TimeInterval,
        mainDelivery: @escaping (@escaping () -> Void) -> Void,
        startAutomatically: Bool = false
    ) {
        self.audioQueue = audioQueue
        self.engine = VolumeRouteEngine(io: io)
        self.writeFlushInterval = writeFlushInterval
        self.mainDelivery = mainDelivery
        super.init()
        if startAutomatically {
            installDeviceChangeListener()
            refreshRoute()
        }
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
        let sequence = beginIntent()
        let willMute = !isMuted
        let restored = rawVolume > 0.001 ? rawVolume : previousVolumeBeforeMute
        enqueueMute(willMute, generation: generation, sequence: sequence)
        publish(
            volume: willMute ? rawVolume : restored,
            muted: willMute, touchDate: true)
        NotchUIEventBus.events.send(
            .sneakPeek(
                type: .volume, value: willMute ? 0 : CGFloat(restored),
                provider: .builtin))
    }

    @MainActor func setAbsolute(_ value: Float32) {
        commit(target: max(0, min(1, value)))
    }

    @MainActor private func commit(target: Float32) {
        guard canAdjustVolume else { return }
        let generation = activeGeneration
        let sequence = beginIntent()
        var muteIntent: Bool?
        if isMuted && target > 0 {
            if usesHardwareMute { muteIntent = false }
        }
        if target == 0 && !isMuted {
            if rawVolume > 0.001 { previousVolumeBeforeMute = rawVolume }
            if usesHardwareMute { muteIntent = true }
        }
        publish(volume: target, muted: target == 0, touchDate: true)
        requestVolumeWrite(target, generation: generation, sequence: sequence)
        // Queue volume intent first so synchronous mute reconciliation sees
        // it and cannot overwrite the optimistic key result with an old level.
        if let muteIntent {
            enqueueMute(muteIntent, generation: generation, sequence: sequence)
        }
        NotchUIEventBus.events.send(
            .sneakPeek(type: .volume, value: CGFloat(target), provider: .builtin))
    }

    @MainActor private func beginIntent() -> UInt64 {
        nextIntentSequence &+= 1
        latestIntentSequence = nextIntentSequence
        return nextIntentSequence
    }

    private func requestVolumeWrite(
        _ value: Float32, generation: UInt64, sequence: UInt64
    ) {
        audioQueue.async { [self] in
            guard engine.queueVolume(
                value, expectedGeneration: generation, sequence: sequence)
            else { return }
            pendingWrite = (generation, sequence)
            guard !writeFlushScheduled else { return }
            writeFlushScheduled = true
            audioQueue.asyncAfter(deadline: .now() + writeFlushInterval) { [self] in
                writeFlushScheduled = false
                guard let pendingWrite else { return }
                self.pendingWrite = nil
                if let observation = engine.flushVolume(
                    expectedGeneration: pendingWrite.generation)
                {
                    deliver(observation)
                }
            }
        }
    }

    private func enqueueMute(_ muted: Bool, generation: UInt64, sequence: UInt64) {
        audioQueue.async { [self] in
            if let observation = engine.setMute(
                muted, expectedGeneration: generation, sequence: sequence)
            {
                deliver(observation)
            }
        }
    }

    func refreshRoute() {
        audioQueue.async { [self] in rebuildRouteLocked() }
    }

    func processRoutePropertyChange(deviceID: AudioObjectID, generation: UInt64) {
        audioQueue.async { [self] in
            guard let observation = engine.handlePropertyEvent(
                deviceID: deviceID, expectedGeneration: generation)
            else { return }
            deliver(observation)
        }
    }

    private func rebuildRouteLocked() {
        removeDeviceListenersLocked()
        pendingWrite = nil
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

    func deliver(_ observation: VolumeRouteObservation) {
        mainDelivery { [weak self] in
            Task { @MainActor in self?.apply(observation) }
        }
    }

    @MainActor func apply(_ observation: VolumeRouteObservation) {
        if observation.isInitialSync {
            guard observation.generation >= activeGeneration else { return }
            activeGeneration = observation.generation
            latestIntentSequence = 0
            rawVolume = observation.volume ?? 0
            isMuted = observation.muted ?? false
            previousVolumeBeforeMute = observation.restoreVolume
        } else {
            guard observation.generation == activeGeneration else { return }
            guard observation.sequence >= latestIntentSequence else { return }
        }
        canAdjustVolume = observation.canAdjustVolume
        canToggleMute = observation.canToggleMute
        usesHardwareMute = observation.usesHardwareMute
        previousVolumeBeforeMute = observation.restoreVolume
        let effectiveMuted = observation.muted ?? isMuted
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
