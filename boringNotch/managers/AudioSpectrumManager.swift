//
//  AudioSpectrumManager.swift
//  boringNotch
//
//  Drives the closed-notch music visualiser from the audio that is actually
//  playing, instead of from random numbers.
//
//  Sound is captured with a Core Audio process tap (macOS 14.2+): a private,
//  mono, system-wide tap is wrapped in a private aggregate device and read
//  through an IOProc. Nothing is ever written to disk — samples land in a ring
//  buffer, get turned into a handful of frequency bands, and are thrown away.
//
//  When the tap is unavailable (older macOS, denied permission, HAL error) the
//  manager reports `isLive == false` and the visualiser falls back to the
//  original random animation.
//

import Accelerate
import AudioToolbox
import Combine
import CoreAudio
import Defaults
import Foundation
import SwiftUI

/// Number of bars the notch visualiser draws.
let audioSpectrumBandCount = 6

// MARK: - Manager

@MainActor
final class AudioSpectrumManager: ObservableObject {
    static let shared = AudioSpectrumManager()

    /// Normalised magnitude per band (0...1), ordered low → high frequency.
    @Published private(set) var levels: [CGFloat] = .init(
        repeating: 0, count: audioSpectrumBandCount
    )

    /// `true` while real audio is driving `levels`.
    @Published private(set) var isLive: Bool = false

    /// Set when the tap could not be started, so settings can explain why.
    @Published private(set) var lastErrorDescription: String?

    private let tap = SystemAudioTap()
    private let processor = SpectrumProcessor(fftSize: 2048)

    /// One token per on-screen visualiser asking for samples. Tokens rather
    /// than a counter, so a view that is torn down without `onDisappear`
    /// cannot leave the tap running forever.
    private var activeTokens = Set<UUID>()
    private var pumpTask: Task<Void, Never>?
    private var teardownTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Envelope state, so bars rise quickly and fall back gently.
    private var envelope: [Float] = .init(repeating: 0, count: audioSpectrumBandCount)

    /// Stall detection: the aggregate device dies when its backing output
    /// device goes away (headphones unplugged, AirPods disconnected).
    private var lastFrameCount = 0
    private var stalledTicks = 0
    private var restartAttempts = 0

    private static let refreshInterval: Duration = .milliseconds(33)  // ~30 fps
    private static let attack: Float = 0.55
    /// Fast enough that bars visibly fall back between hits during a dense
    /// chorus instead of sitting pinned near the top.
    private static let release: Float = 0.22
    /// ~1.5 s of no new audio frames before rebuilding the tap.
    private static let stallTickLimit = 45
    /// Give up rebuilding after this many fruitless attempts and let the
    /// visualiser fall back to its animation rather than thrash the HAL.
    private static let maxRestartAttempts = 3
    /// How long the tap survives after the last visualiser lets go.
    private static let teardownGrace: Duration = .seconds(5)

    private init() {
        Defaults.publisher(.realtimeAudioSpectrum)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self else { return }
                    if change.newValue {
                        self.lastErrorDescription = nil
                        self.startIfNeeded()
                    } else {
                        self.teardown()
                    }
                }
            }
            .store(in: &cancellables)

        // Safety net: never hold a tap open once playback has stopped, even if
        // a visualiser disappeared without telling us. The live value is read
        // inside the hop rather than taken from the event, because a track
        // change emits false then true in quick succession and the stale
        // `false` would otherwise tear down a tap that has just been rebuilt.
        MusicManager.shared.$isPlaying
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, !MusicManager.shared.isPlaying else { return }
                    self.activeTokens.removeAll()
                    self.scheduleTeardown()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Subscription

    /// Called by a visualiser when it appears or starts playing. Idempotent.
    func activate(_ token: UUID) {
        teardownTask?.cancel()
        teardownTask = nil
        let (inserted, _) = activeTokens.insert(token)
        guard inserted else { return }
        startIfNeeded()
    }

    /// Called by a visualiser when it disappears or stops playing.
    func deactivate(_ token: UUID) {
        guard activeTokens.remove(token) != nil else { return }
        if activeTokens.isEmpty {
            scheduleTeardown()
        }
    }

    /// Tearing the tap down is deferred, because a track change briefly reports
    /// "not playing" and rebuilding a Core Audio tap on every track boundary is
    /// both wasteful and a source of races.
    private func scheduleTeardown() {
        guard pumpTask != nil, teardownTask == nil else { return }
        teardownTask = Task { [weak self] in
            try? await Task.sleep(for: Self.teardownGrace)
            guard !Task.isCancelled, let self else { return }
            self.teardownTask = nil
            guard self.activeTokens.isEmpty else { return }
            self.teardown()
        }
    }

    /// Re-attempts a tap that previously failed (used by the settings toggle).
    func retry() {
        lastErrorDescription = nil
        teardown()
        startIfNeeded()
    }

    // MARK: Lifecycle

    private func startIfNeeded() {
        guard Defaults[.realtimeAudioSpectrum], !activeTokens.isEmpty, pumpTask == nil else {
            return
        }

        do {
            try tap.start()
            lastErrorDescription = nil
            isLive = true
        } catch {
            lastErrorDescription = error.localizedDescription
            isLive = false
            tap.stop()
            return
        }

        lastFrameCount = tap.totalFramesCaptured
        stalledTicks = 0
        restartAttempts = 0

        pumpTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled, let self else { return }
                self.pump()
            }
        }
    }

    private func teardown() {
        teardownTask?.cancel()
        teardownTask = nil
        pumpTask?.cancel()
        pumpTask = nil
        tap.stop()
        isLive = false
        processor.resetAdaptation()
        envelope = .init(repeating: 0, count: audioSpectrumBandCount)
        stalledTicks = 0
        lastFrameCount = 0
        restartAttempts = 0
        if levels.contains(where: { $0 != 0 }) {
            levels = .init(repeating: 0, count: audioSpectrumBandCount)
        }
    }

    private func pump() {
        checkForStall()

        guard
            let bands = processor.analyze(
                from: tap,
                dynamicSensitivity: Defaults[.dynamicSpectrumSensitivity]
            )
        else {
            // Not enough audio yet: decay towards rest.
            applyEnvelope(to: .init(repeating: 0, count: audioSpectrumBandCount))
            return
        }
        applyEnvelope(to: bands)
    }

    /// Rebuilds the tap when the HAL stops delivering frames, which happens
    /// when the output device the aggregate was built around disappears.
    /// Without the auto-start key the device feeds silence rather than nothing,
    /// so a frame counter that stops advancing really does mean a dead device.
    private func checkForStall() {
        let frames = tap.totalFramesCaptured
        guard frames == lastFrameCount else {
            stalledTicks = 0
            restartAttempts = 0
            lastFrameCount = frames
            return
        }

        stalledTicks += 1
        guard stalledTicks >= Self.stallTickLimit else { return }
        stalledTicks = 0

        guard restartAttempts < Self.maxRestartAttempts else {
            // Something is wrong that rebuilding will not fix. Stand down and
            // let the visualiser use its fallback animation; the next
            // play/pause cycle starts a fresh attempt.
            teardown()
            return
        }
        restartAttempts += 1

        tap.stop()
        do {
            try tap.start()
            isLive = true
        } catch {
            lastErrorDescription = error.localizedDescription
            isLive = false
        }
        lastFrameCount = tap.totalFramesCaptured
    }

    private func applyEnvelope(to target: [Float]) {
        var changed = false
        var next = levels
        for index in 0..<audioSpectrumBandCount {
            let goal = target[index]
            let coefficient = goal > envelope[index] ? Self.attack : Self.release
            envelope[index] += (goal - envelope[index]) * coefficient
            // Quantise so tiny fluctuations do not re-render the notch.
            let rounded = CGFloat((envelope[index] * 100).rounded() / 100)
            if rounded != next[index] {
                next[index] = rounded
                changed = true
            }
        }
        if changed {
            levels = next
        }
    }
}

// MARK: - FFT

/// Turns raw mono samples into a small number of normalised frequency bands.
private final class SpectrumProcessor {
    private let fftSize: Int
    private let halfSize: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup

    private var window: [Float]
    private var windowed: [Float]
    private var realPart: [Float]
    private var imaginaryPart: [Float]
    private var magnitudes: [Float]
    private var samples: [Float]

    /// Roughly octave-and-a-half band edges in Hz. Wide-ish spacing keeps each
    /// band's level close to its neighbour's, so the bars sit on a common scale
    /// without a large correction.
    private let bandEdges: [Float] = [60, 150, 400, 1000, 2500, 6000, 14000]

    /// Slow per-band reference level (dB), used to cancel the material's own
    /// spectral tilt. A fixed per-band gain cannot do this: the gap between the
    /// bass and treble bands ranges from roughly 25 dB to 50 dB depending on the
    /// track, so any constant is badly wrong for most music — too small and the
    /// treble bars never move, too large and every band pins at the top during a
    /// chorus and the four bars flatten into a line.
    private var reference: [Float] = .init(repeating: -60, count: audioSpectrumBandCount)
    private var referencePrimed = false

    /// ~1.6 s at 30 fps: slow enough to describe the track, fast enough to
    /// follow a change of instrumentation.
    private let adaptCoefficient: Float = 0.02
    /// Deliberately short of 1.0: fully flattening the spectrum makes all eight
    /// bars statistically identical, which reads as a flat line. This leaves a
    /// gentle bass-heavy slope, the way a real analyser looks.
    private let adaptStrength: Float = 0.75
    private let balanceLimits: ClosedRange<Float> = -12 ... 55

    /// Below this the band is treated as silence and left out of the reference,
    /// so gaps between tracks do not drag it down.
    private let signalGateDB: Float = -85

    /// The 0...1 window follows a slow average of the music instead of fixed dB
    /// thresholds. Absolute levels coming out of the tap depend on the track's
    /// mastering and on how the source app renders — three attempts at fixed
    /// thresholds each looked right on synthetic signals and then pinned every
    /// bar at full height on real music. Anchoring the window to the material
    /// removes that calibration guess entirely.
    private var levelReference: Float = -60
    private var levelPrimed = false

    /// ~6.5 s at 30 fps: long enough that a chorus still reads as louder than a
    /// verse, short enough to re-centre on a different track or output device.
    private let levelCoefficient: Float = 0.005
    /// dB below / above the running average that map to an empty / full bar.
    private let spanBelow: Float = 15
    private let spanAbove: Float = 15

    /// Extra dB added to the top of the window when the music is loud enough
    /// that the bars would otherwise all sit pinned at full height. Unlike the
    /// slow `levelReference`, this reacts within a few frames, so a heavily
    /// compressed master cannot flatten the display while the average catches
    /// up. It relaxes back to zero whenever the peak leaves the ceiling alone,
    /// so it is inaudible — visually — on material that never saturates.
    private var headroom: Float = 0
    private let headroomMargin: Float = 2
    private let headroomAttack: Float = 0.5
    private let headroomRelease: Float = 0.06
    private let maxHeadroom: Float = 24

    init(fftSize: Int) {
        self.fftSize = fftSize
        halfSize = fftSize / 2
        log2n = vDSP_Length(log2(Float(fftSize)).rounded())
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        window = .init(repeating: 0, count: fftSize)
        windowed = .init(repeating: 0, count: fftSize)
        realPart = .init(repeating: 0, count: halfSize)
        imaginaryPart = .init(repeating: 0, count: halfSize)
        magnitudes = .init(repeating: 0, count: halfSize)
        samples = .init(repeating: 0, count: fftSize)

        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_DENORM))
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Returns one normalised value per band, or `nil` if the tap has no audio yet.
    func analyze(from tap: SystemAudioTap, dynamicSensitivity: Bool) -> [Float]? {
        guard tap.copyLatestSamples(into: &samples) else { return nil }

        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        windowed.withUnsafeBufferPointer { input in
            realPart.withUnsafeMutableBufferPointer { real in
                imaginaryPart.withUnsafeMutableBufferPointer { imaginary in
                    var split = DSPSplitComplex(
                        realp: real.baseAddress!, imagp: imaginary.baseAddress!
                    )
                    input.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self, capacity: halfSize
                    ) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(halfSize))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    magnitudes.withUnsafeMutableBufferPointer { output in
                        vDSP_zvabs(&split, 1, output.baseAddress!, 1, vDSP_Length(halfSize))
                    }
                }
            }
        }

        // vDSP's packed real FFT returns values scaled by 2 * fftSize.
        var scale = Float(1) / Float(2 * fftSize)
        magnitudes.withUnsafeMutableBufferPointer { output in
            vDSP_vsmul(
                output.baseAddress!, 1, &scale, output.baseAddress!, 1, vDSP_Length(halfSize)
            )
        }

        let binWidth = Float(tap.sampleRate) / Float(fftSize)
        guard binWidth > 0 else { return nil }

        var raw = [Float](repeating: -160, count: audioSpectrumBandCount)
        for band in 0..<audioSpectrumBandCount {
            let lowBin = max(1, Int((bandEdges[band] / binWidth).rounded(.down)))
            let highBin = min(halfSize - 1, Int((bandEdges[band + 1] / binWidth).rounded(.up)))
            guard highBin >= lowBin else { continue }

            var meanSquare: Float = 0
            let count = vDSP_Length(highBin - lowBin + 1)
            magnitudes.withUnsafeBufferPointer { pointer in
                vDSP_measqv(pointer.baseAddress! + lowBin, 1, &meanSquare, count)
            }
            raw[band] = 20 * log10(max(sqrt(meanSquare), 1e-9))
        }

        updateReference(with: raw)

        // Correct only the gap between bands, so overall loudness still reaches
        // the bars unchanged.
        let balanced = (0..<audioSpectrumBandCount).map { band -> Float in
            let balance = min(
                max((reference[0] - reference[band]) * adaptStrength, balanceLimits.lowerBound),
                balanceLimits.upperBound
            )
            return raw[band] + balance
        }

        updateLevelReference(with: balanced)
        updateHeadroom(peak: balanced.max() ?? -160, enabled: dynamicSensitivity)

        let low = levelReference - spanBelow
        let span = spanBelow + spanAbove + headroom
        return balanced.map { min(max(($0 - low) / span, 0), 1) }
    }

    /// Widens the top of the window while the loudest band is crowding it.
    private func updateHeadroom(peak: Float, enabled: Bool) {
        guard enabled else {
            headroom = 0
            return
        }
        let ceiling = levelReference + spanAbove + headroom
        let excess = peak - (ceiling - headroomMargin)
        if excess > 0 {
            headroom = min(headroom + excess * headroomAttack, maxHeadroom)
        } else {
            headroom = max(0, headroom - headroomRelease)
        }
    }

    private func updateLevelReference(with balanced: [Float]) {
        guard balanced[0] > signalGateDB else { return }
        let mean = balanced.reduce(0, +) / Float(audioSpectrumBandCount)
        if !levelPrimed {
            levelReference = mean
            levelPrimed = true
            return
        }
        levelReference += (mean - levelReference) * levelCoefficient
    }

    private func updateReference(with raw: [Float]) {
        guard raw[0] > signalGateDB else { return }

        if !referencePrimed {
            reference = raw
            referencePrimed = true
            return
        }
        for band in 0..<audioSpectrumBandCount {
            reference[band] += (raw[band] - reference[band]) * adaptCoefficient
        }
    }

    /// Forgets the learnt spectral balance, e.g. when the tap is rebuilt.
    func resetAdaptation() {
        referencePrimed = false
        reference = .init(repeating: -60, count: audioSpectrumBandCount)
        levelPrimed = false
        levelReference = -60
        headroom = 0
    }
}

// MARK: - Core Audio process tap

enum SystemAudioTapError: LocalizedError {
    case unsupportedOS
    case tapCreationFailed(OSStatus)
    case aggregateCreationFailed(OSStatus)
    case ioProcFailed(OSStatus)
    case startFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return String(localized: "Real-time audio requires macOS 14.2 or later.")
        case let .tapCreationFailed(status):
            // The HAL refuses to create a tap until the audio recording
            // permission has been granted.
            return String(
                localized:
                    "Could not tap system audio (error \(status)). Allow boringNotch to record system audio in System Settings › Privacy & Security."
            )
        case let .aggregateCreationFailed(status):
            return String(localized: "Could not create the audio capture device (error \(status)).")
        case let .ioProcFailed(status):
            return String(localized: "Could not read the audio capture device (error \(status)).")
        case let .startFailed(status):
            return String(localized: "Could not start audio capture (error \(status)).")
        }
    }
}

/// A private, system-wide, mono Core Audio tap feeding a lock-protected ring buffer.
final class SystemAudioTap {
    private static let ringCapacity = 8192  // power of two
    private static let ringMask = ringCapacity - 1

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    private let ioQueue = DispatchQueue(
        label: "theboringteam.boringnotch.audiotap", qos: .userInitiated
    )
    private let lock = NSLock()
    private var ring = [Float](repeating: 0, count: SystemAudioTap.ringCapacity)
    private var writeIndex = 0
    private var storedSampleRate: Double = 48000

    /// Nominal sample rate of the capture device.
    var sampleRate: Double {
        lock.lock()
        defer { lock.unlock() }
        return storedSampleRate
    }

    /// Total frames seen since the tap started; used to detect a dead device.
    var totalFramesCaptured: Int {
        lock.lock()
        defer { lock.unlock() }
        return writeIndex
    }

    // MARK: Start / stop

    func start() throws {
        guard #available(macOS 14.2, *) else { throw SystemAudioTapError.unsupportedOS }
        guard aggregateID == AudioObjectID(kAudioObjectUnknown) else { return }

        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "boringNotch Visualiser"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTapID)
        guard tapStatus == noErr, newTapID != AudioObjectID(kAudioObjectUnknown) else {
            throw SystemAudioTapError.tapCreationFailed(tapStatus)
        }
        tapID = newTapID

        do {
            aggregateID = try Self.makeAggregateDevice(tapUID: description.uuid.uuidString)
        } catch {
            stop()
            throw error
        }

        let rate = Self.nominalSampleRate(of: aggregateID) ?? 48000
        lock.lock()
        storedSampleRate = rate
        writeIndex = 0
        lock.unlock()

        var newProcID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(
            &newProcID, aggregateID, ioQueue
        ) { [weak self] _, inputData, _, _, _ in
            self?.consume(inputData)
        }
        guard procStatus == noErr, let newProcID else {
            stop()
            throw SystemAudioTapError.ioProcFailed(procStatus)
        }
        ioProcID = newProcID

        let startStatus = AudioDeviceStart(aggregateID, newProcID)
        guard startStatus == noErr else {
            stop()
            throw SystemAudioTapError.startFailed(startStatus)
        }
    }

    func stop() {
        if let ioProcID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil

        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != AudioObjectID(kAudioObjectUnknown) {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }

        lock.lock()
        writeIndex = 0
        lock.unlock()
    }

    // MARK: Sample access

    /// Fills `buffer` with the newest samples, oldest first.
    /// Returns `false` until enough audio has been captured.
    func copyLatestSamples(into buffer: inout [Float]) -> Bool {
        let wanted = buffer.count
        guard wanted <= Self.ringCapacity else { return false }

        lock.lock()
        defer { lock.unlock() }
        guard writeIndex >= wanted else { return false }

        let start = writeIndex - wanted
        for offset in 0..<wanted {
            buffer[offset] = ring[(start + offset) & Self.ringMask]
        }
        return true
    }

    // MARK: IOProc

    private func consume(_ inputData: UnsafePointer<AudioBufferList>) {
        let bufferList = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )
        guard let buffer = bufferList.first, let raw = buffer.mData else { return }

        let channels = max(1, Int(buffer.mNumberChannels))
        let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        guard frames > 0 else { return }

        let samples = raw.assumingMemoryBound(to: Float.self)

        lock.lock()
        for frame in 0..<frames {
            ring[writeIndex & Self.ringMask] = samples[frame * channels]
            writeIndex += 1
        }
        lock.unlock()
    }

    // MARK: Aggregate device

    private static func makeAggregateDevice(tapUID: String) throws -> AudioObjectID {
        let tapEntry: [String: Any] = [
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: true,
        ]

        // Deliberately *not* using kAudioAggregateDeviceTapAutoStartKey: it makes
        // AudioDeviceStart wait until a tapped process *begins* receiving audio.
        // A tap built in the middle of an already-playing stream would then never
        // start, which froze the bars whenever the tap was rebuilt mid-track.
        var description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "boringNotch Visualiser",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapListKey: [tapEntry],
        ]

        // Anchoring the aggregate to the current output device gives it a clock.
        if let outputUID = defaultOutputDeviceUID() {
            description[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
            description[kAudioAggregateDeviceSubDeviceListKey] = [
                [kAudioSubDeviceUIDKey: outputUID]
            ]
        }

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateAggregateDevice(
            description as CFDictionary, &deviceID
        )

        if status != noErr {
            // Retry tap-only; some output devices refuse to be aggregated
            // (virtual devices, Bluetooth in certain modes).
            description.removeValue(forKey: kAudioAggregateDeviceMainSubDeviceKey)
            description[kAudioAggregateDeviceSubDeviceListKey] = [Any]()
            deviceID = AudioObjectID(kAudioObjectUnknown)
            status = AudioHardwareCreateAggregateDevice(
                description as CFDictionary, &deviceID
            )
        }

        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
            throw SystemAudioTapError.aggregateCreationFailed(status)
        }
        return deviceID
    }

    private static func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
            ) == noErr,
            deviceID != AudioObjectID(kAudioObjectUnknown)
        else { return nil }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: CFString?
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        guard
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &uidSize, &uid) == noErr
        else { return nil }
        return uid as String?
    }

    private static func nominalSampleRate(of deviceID: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate) == noErr,
            rate > 0
        else { return nil }
        return rate
    }
}
