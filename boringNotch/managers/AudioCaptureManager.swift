//
//  AudioCaptureManager.swift
//  boringNotch
//
//  Captures audio from the currently-playing music app via Core Audio
//  Process Tap (macOS 14.2+), runs an FFT via Accelerate, and publishes
//  6 log-spaced magnitude bands for the visualizer.
//

import Accelerate
import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Defaults
import Foundation
import os

final class AudioCaptureManager: ObservableObject {
    static let shared = AudioCaptureManager()

    static let barCount = 6
    private static let fftSize = 1024
    private static let log2n: vDSP_Length = 10
    private static let ringCapacity = 4096
    private static let floorDB: Float = -50
    private static let ceilDB: Float = -25
    private static let referenceHz: Double = 1000
    private static let fftQueueKey = DispatchSpecificKey<Void>()

    let levelsPublisher = PassthroughSubject<[Float], Never>()
    @Published private(set) var isCapturing: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private var tapObjectID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioDeviceID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var currentPID: pid_t = 0
    private var sampleRate: Double = 48_000

    private let ringBuffer: UnsafeMutablePointer<Float>
    private var ringWrite: Int = 0
    private let ringLock = OSAllocatedUnfairLock()

    private let fft: vDSP.FFT<DSPSplitComplex>
    private let hannWindow: [Float]
    private let windowPowerScalar: Float
    private var samplesBuf: [Float]
    private var windowedBuf: [Float]
    private var realBuf: [Float]
    private var imagBuf: [Float]
    private var powBuf: [Float]
    private var smoothed: [Float]
    private var barsBuf: [Float]
    private var lastPublishedBuf: [Float]
    private var bandRanges: [Range<Int>] = []
    private var pinkCompensationDB: [Float] = []

    private let fftQueue = DispatchQueue(label: "com.boringnotch.audiocapture.fft", qos: .userInitiated)
    private var fftTimer: DispatchSourceTimer?

    private init() {
        ringBuffer = UnsafeMutablePointer<Float>.allocate(capacity: Self.ringCapacity)
        ringBuffer.initialize(repeating: 0, count: Self.ringCapacity)

        guard let setup = vDSP.FFT(log2n: Self.log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
            fatalError("Failed to create vDSP.FFT setup")
        }
        fft = setup
        let window = vDSP.window(
            ofType: Float.self,
            usingSequence: .hanningDenormalized,
            count: Self.fftSize,
            isHalfWindow: false
        )
        hannWindow = window
        // Parseval-style normalization so full-scale input lands near 0 dBFS.
        // Factor of 2 folds the one-sided real FFT back to total power.
        let windowPowerGain = vDSP.sum(vDSP.multiply(window, window))
        windowPowerScalar = 2.0 / (Float(Self.fftSize) * windowPowerGain)
        samplesBuf = [Float](repeating: 0, count: Self.fftSize)
        windowedBuf = [Float](repeating: 0, count: Self.fftSize)
        realBuf = [Float](repeating: 0, count: Self.fftSize / 2)
        imagBuf = [Float](repeating: 0, count: Self.fftSize / 2)
        powBuf = [Float](repeating: 0, count: Self.fftSize / 2)
        smoothed = [Float](repeating: 0, count: Self.barCount)
        barsBuf = [Float](repeating: 0, count: Self.barCount)
        // Seed with a sentinel so the first real frame always publishes.
        lastPublishedBuf = [Float](repeating: -1, count: Self.barCount)

        fftQueue.setSpecific(key: Self.fftQueueKey, value: ())
        computeBandRanges(sampleRate: sampleRate)
        observeState()
    }

    deinit {
        teardownCapture()
        ringBuffer.deinitialize(count: Self.ringCapacity)
        ringBuffer.deallocate()
    }

    // MARK: - State observation

    private func observeState() {
        let music = MusicManager.shared
        let enabledPublisher = Defaults.publisher(.realtimeAudioWaveform)
            .map(\.newValue)
            .prepend(Defaults[.realtimeAudioWaveform])

        Publishers.CombineLatest3(music.$isPlaying, music.$bundleIdentifier, enabledPublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying, bundleID, enabled in
                self?.evaluate(isPlaying: isPlaying, bundleID: bundleID, enabled: enabled)
            }
            .store(in: &cancellables)
    }

    private func evaluate(isPlaying: Bool, bundleID: String?, enabled: Bool) {
        guard #available(macOS 14.2, *),
              enabled, isPlaying,
              let bundleID, !bundleID.isEmpty,
              let pid = resolvePID(forBundleID: bundleID) else {
            if isCapturing { stopCapture() }
            return
        }
        if isCapturing && pid == currentPID { return }
        if isCapturing { stopCapture() }
        startCapture(pid: pid)
    }

    private func resolvePID(forBundleID bundleID: String) -> pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first?
            .processIdentifier
    }

    // MARK: - Capture lifecycle

    @available(macOS 14.2, *)
    private func startCapture(pid: pid_t) {
        currentPID = pid

        guard let processObjectID = translatePIDToAudioObject(pid: pid) else {
            NSLog("[AudioCaptureManager] Failed to translate PID \(pid) to AudioObjectID")
            return
        }

        let tapDescription = CATapDescription(monoMixdownOfProcesses: [processObjectID])
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true
        tapDescription.isExclusive = false

        var newTapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard tapStatus == noErr, newTapID != kAudioObjectUnknown else {
            NSLog("[AudioCaptureManager] AudioHardwareCreateProcessTap failed: \(tapStatus)")
            return
        }
        tapObjectID = newTapID

        guard let tapUID = getAudioObjectStringProperty(
            objectID: tapObjectID,
            selector: kAudioTapPropertyUID
        ) else {
            NSLog("[AudioCaptureManager] Failed to read tap UID")
            cleanupTap()
            return
        }

        var streamFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let fmtStatus = AudioObjectGetPropertyData(
            tapObjectID, &formatAddr, 0, nil, &formatSize, &streamFormat
        )
        if fmtStatus == noErr, streamFormat.mSampleRate > 0 {
            sampleRate = streamFormat.mSampleRate
            computeBandRanges(sampleRate: sampleRate)
        }

        let aggregateUID = "com.boringnotch.audiotap.\(UUID().uuidString)"
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "boringNotchTapAggregate",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: "",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: 0
                ]
            ]
        ]

        var newAggID: AudioDeviceID = 0
        let aggStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary, &newAggID
        )
        guard aggStatus == noErr, newAggID != 0 else {
            NSLog("[AudioCaptureManager] AudioHardwareCreateAggregateDevice failed: \(aggStatus)")
            cleanupTap()
            return
        }
        aggregateDeviceID = newAggID

        var newIOProc: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
            &newIOProc, aggregateDeviceID, fftQueue
        ) { [weak self] _, inInputData, _, _, _ in
            self?.handleInputBuffer(inInputData)
        }
        guard ioStatus == noErr, let ioProc = newIOProc else {
            NSLog("[AudioCaptureManager] AudioDeviceCreateIOProcIDWithBlock failed: \(ioStatus)")
            cleanupAggregate()
            cleanupTap()
            return
        }
        ioProcID = ioProc

        let startStatus = AudioDeviceStart(aggregateDeviceID, ioProc)
        guard startStatus == noErr else {
            NSLog("[AudioCaptureManager] AudioDeviceStart failed: \(startStatus)")
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProc)
            ioProcID = nil
            cleanupAggregate()
            cleanupTap()
            return
        }

        startFFTTimer()
        isCapturing = true
    }

    private func stopCapture() {
        stopFFTTimer()
        teardownCapture()
        currentPID = 0
        syncOnFFTQueue {
            ringLock.lock()
            ringBuffer.update(repeating: 0, count: Self.ringCapacity)
            ringWrite = 0
            ringLock.unlock()
            for i in 0..<Self.barCount {
                smoothed[i] = 0
                barsBuf[i] = 0
                lastPublishedBuf[i] = -1
            }
        }
        let zeros = [Float](repeating: 0, count: Self.barCount)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.levelsPublisher.send(zeros)
            self.isCapturing = false
        }
    }

    private func teardownCapture() {
        if aggregateDeviceID != 0, let proc = ioProcID {
            AudioDeviceStop(aggregateDeviceID, proc)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, proc)
        }
        ioProcID = nil
        cleanupAggregate()
        cleanupTap()
    }

    private func cleanupAggregate() {
        if aggregateDeviceID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = 0
        }
    }

    private func cleanupTap() {
        guard tapObjectID != kAudioObjectUnknown else { return }
        if #available(macOS 14.2, *) {
            AudioHardwareDestroyProcessTap(tapObjectID)
        }
        tapObjectID = kAudioObjectUnknown
    }

    // MARK: - IO proc

    private func handleInputBuffer(_ bufferList: UnsafePointer<AudioBufferList>) {
        let mutableBL = UnsafeMutablePointer(mutating: bufferList)
        let abl = UnsafeMutableAudioBufferListPointer(mutableBL)
        guard let first = abl.first, let rawData = first.mData else { return }
        // Tap is configured with monoMixdownOfProcesses, so we always receive one channel.
        assert(first.mNumberChannels == 1)
        let frameCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard frameCount > 0 else { return }
        let src = rawData.assumingMemoryBound(to: Float.self)

        ringLock.lock()
        let cap = Self.ringCapacity
        let write = ringWrite
        let firstCount = min(frameCount, cap - write)
        memcpy(ringBuffer.advanced(by: write), src, firstCount * MemoryLayout<Float>.size)
        if firstCount < frameCount {
            memcpy(
                ringBuffer,
                src.advanced(by: firstCount),
                (frameCount - firstCount) * MemoryLayout<Float>.size
            )
        }
        ringWrite = (write + frameCount) % cap
        ringLock.unlock()
    }

    // MARK: - FFT loop

    private func startFFTTimer() {
        let timer = DispatchSource.makeTimerSource(queue: fftQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33))
        timer.setEventHandler { [weak self] in self?.processFFT() }
        fftTimer = timer
        timer.resume()
    }

    private func stopFFTTimer() {
        fftTimer?.cancel()
        fftTimer = nil
    }

    private func syncOnFFTQueue(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: Self.fftQueueKey) != nil {
            work()
        } else {
            fftQueue.sync(execute: work)
        }
    }

    private func processFFT() {
        let n = Self.fftSize

        ringLock.lock()
        let cap = Self.ringCapacity
        let end = ringWrite
        let start = (end - n + cap) % cap
        samplesBuf.withUnsafeMutableBufferPointer { dst in
            guard let base = dst.baseAddress else { return }
            if start + n <= cap {
                memcpy(base, ringBuffer.advanced(by: start), n * MemoryLayout<Float>.size)
            } else {
                let firstCount = cap - start
                memcpy(base, ringBuffer.advanced(by: start), firstCount * MemoryLayout<Float>.size)
                memcpy(
                    base.advanced(by: firstCount),
                    ringBuffer,
                    (n - firstCount) * MemoryLayout<Float>.size
                )
            }
        }
        ringLock.unlock()

        vDSP.multiply(samplesBuf, hannWindow, result: &windowedBuf)

        let halfN = n / 2
        realBuf.withUnsafeMutableBufferPointer { rPtr in
            imagBuf.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                windowedBuf.withUnsafeBufferPointer { wPtr in
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cPtr in
                        vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfN))
                    }
                }
                fft.forward(input: split, output: &split)
                // vDSP packs DC in realp[0] and Nyquist in imagp[0]; zero both
                // so they can't pollute the sub-bass band.
                rPtr[0] = 0
                iPtr[0] = 0
                vDSP.squareMagnitudes(split, result: &powBuf)
            }
        }
        vDSP.multiply(windowPowerScalar, powBuf, result: &powBuf)

        let floorDB = Self.floorDB
        let ceilDB = Self.ceilDB
        let dbRange = ceilDB - floorDB
        powBuf.withUnsafeBufferPointer { pPtr in
            guard let base = pPtr.baseAddress else { return }
            for i in 0..<Self.barCount {
                let range = bandRanges[i]
                guard !range.isEmpty else { barsBuf[i] = 0; continue }
                var sum: Float = 0
                vDSP_sve(base.advanced(by: range.lowerBound), 1, &sum, vDSP_Length(range.count))
                let meanPow = sum / Float(range.count)
                let db = 10 * log10f(max(meanPow, 1e-12)) + pinkCompensationDB[i]
                let clamped = max(floorDB, min(ceilDB, db))
                barsBuf[i] = (clamped - floorDB) / dbRange
            }
        }

        var maxDelta: Float = 0
        for i in 0..<Self.barCount {
            let target = barsBuf[i]
            let decayed = smoothed[i] * 0.82
            let next = target > decayed ? (decayed + (target - decayed) * 0.6) : decayed
            smoothed[i] = next
            let clipped = max(0, min(1, next))
            barsBuf[i] = clipped
            let delta = abs(clipped - lastPublishedBuf[i])
            if delta > maxDelta { maxDelta = delta }
        }

        // Skip the hop to main + Combine fan-out when nothing perceptible changed.
        // Stacks with the view-side threshold to collapse idle cost toward zero.
        guard maxDelta > 1e-4 else { return }
        for i in 0..<Self.barCount {
            lastPublishedBuf[i] = barsBuf[i]
        }
        let snapshot = barsBuf
        levelsPublisher.send(snapshot)
    }

    private func computeBandRanges(sampleRate: Double) {
        let halfN = Self.fftSize / 2
        let nyquist = sampleRate / 2
        let minHz: Double = 60
        let maxHz: Double = min(16_000, nyquist - 1)
        guard maxHz > minHz else {
            bandRanges = Array(repeating: 0..<0, count: Self.barCount)
            pinkCompensationDB = Array(repeating: 0, count: Self.barCount)
            return
        }
        let logMin = log(minHz)
        let logMax = log(maxHz)
        var ranges: [Range<Int>] = []
        var pinks: [Float] = []
        for i in 0..<Self.barCount {
            let startHz = exp(logMin + (logMax - logMin) * Double(i) / Double(Self.barCount))
            let endHz = exp(logMin + (logMax - logMin) * Double(i + 1) / Double(Self.barCount))
            let startBin = max(1, Int((startHz / nyquist) * Double(halfN)))
            let endBin = max(startBin + 1, min(halfN, Int((endHz / nyquist) * Double(halfN))))
            ranges.append(startBin..<endBin)
            let centerHz = sqrt(startHz * endHz)
            pinks.append(Float(3.0 * log2(centerHz / Self.referenceHz)))
        }
        bandRanges = ranges
        pinkCompensationDB = pinks
    }

    // MARK: - Core Audio helpers

    private func translatePIDToAudioObject(pid: pid_t) -> AudioObjectID? {
        var pidVal = pid
        var processObject: AudioObjectID = kAudioObjectUnknown
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            UInt32(MemoryLayout<pid_t>.size),
            &pidVal,
            &size,
            &processObject
        )
        guard status == noErr, processObject != kAudioObjectUnknown else { return nil }
        return processObject
    }

    private func getAudioObjectStringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cfStr: CFString?
        let status = withUnsafeMutablePointer(to: &cfStr) { ptr in
            AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr, let cfStr = cfStr else { return nil }
        return cfStr as String
    }
}
