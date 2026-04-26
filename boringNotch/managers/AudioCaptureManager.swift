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
import Darwin
import Defaults
import Foundation

protocol AudioCaptureLevelsConsumer: AnyObject {
    func audioCaptureManager(_ manager: AudioCaptureManager, didProduceLevels values: [Float])
}

final class AudioCaptureManager: ObservableObject {
    static let shared = AudioCaptureManager()

    static let barCount = 6
    private static let fftSize = 1024
    private static let log2n: vDSP_Length = 10
    private static let ringCapacity = 4096
    private static let fftIntervalMilliseconds = 33
    private static let fftLeewayMilliseconds = 0
    private static let floorDB: Float = -58
    private static let ceilDB: Float = -14
    private static let referenceHz: Double = 1000
    private static let pinkCompensationSlopePerOctave: Double = 3.0
    private static let fftQueueKey = DispatchSpecificKey<Void>()
    private static let lifecycleQueueKey = DispatchSpecificKey<Void>()
    private static let allowedAlreadyDestroyedStatuses: Set<OSStatus> = [
        kAudioHardwareBadObjectError,
        kAudioHardwareUnknownPropertyError
    ]

    @Published private(set) var isCapturing: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private var tapObjectID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioDeviceID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var currentPIDs: [pid_t] = []
    private var sampleRate: Double = 48_000

    private let ringBuffer: UnsafeMutablePointer<Float>
    private var ringWrite: Int = 0
    private let ringLock = OSAllocatedUnfairLock()
    private let levelsConsumerLock = OSAllocatedUnfairLock()
    private let levelsConsumers = NSHashTable<AnyObject>.weakObjects()
    private var latestLevels: [Float]?

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
    private let ioQueue = DispatchQueue(label: "com.boringnotch.audiocapture.io", qos: .userInteractive)
    private let lifecycleQueue = DispatchQueue(label: "com.boringnotch.audiocapture.lifecycle", qos: .userInitiated)
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
        lifecycleQueue.setSpecific(key: Self.lifecycleQueueKey, value: ())
        computeBandRanges(sampleRate: sampleRate)
        observeState()
    }

    deinit {
        syncOnLifecycleQueue {
            stopCaptureOnLifecycleQueue()
        }
        ringBuffer.deinitialize(count: Self.ringCapacity)
        ringBuffer.deallocate()
    }

    func setLevelsConsumer(_ consumer: AudioCaptureLevelsConsumer) {
        levelsConsumerLock.lock()
        defer { levelsConsumerLock.unlock() }
        levelsConsumers.add(consumer)
    }

    func clearLevelsConsumer(_ consumer: AudioCaptureLevelsConsumer) {
        levelsConsumerLock.lock()
        defer { levelsConsumerLock.unlock() }
        levelsConsumers.remove(consumer)
    }

    func latestLevelsSnapshot() -> [Float]? {
        levelsConsumerLock.lock()
        defer { levelsConsumerLock.unlock() }
        return latestLevels
    }

    // MARK: - State observation

    private func observeState() {
        let music = MusicManager.shared
        let enabledPublisher = Defaults.publisher(.realtimeAudioWaveform)
            .map(\.newValue)
            .prepend(Defaults[.realtimeAudioWaveform])
            .removeDuplicates()

        Publishers.CombineLatest4(
            music.$isPlaying.removeDuplicates(),
            music.$bundleIdentifier.removeDuplicates(),
            music.$audioCaptureBundleIdentifiers.removeDuplicates(),
            enabledPublisher
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying, bundleID, captureBundleIDs, enabled in
                self?.evaluate(
                    isPlaying: isPlaying,
                    displayBundleID: bundleID,
                    captureBundleIDs: captureBundleIDs,
                    enabled: enabled
                )
            }
            .store(in: &cancellables)
    }

    private func evaluate(
        isPlaying: Bool,
        displayBundleID: String?,
        captureBundleIDs: [String],
        enabled: Bool
    ) {
        guard #available(macOS 14.2, *),
              enabled, isPlaying,
              let resolvedDisplayBundleID = displayBundleID,
              !resolvedDisplayBundleID.isEmpty else {
            stopCaptureAsync()
            return
        }
        let resolvedPIDs = resolvePIDs(
            displayBundleID: resolvedDisplayBundleID,
            captureBundleIDs: captureBundleIDs
        )
        guard !resolvedPIDs.isEmpty else {
            stopCaptureAsync()
            return
        }
        lifecycleQueue.async { [weak self] in
            self?.startCaptureOnLifecycleQueue(pids: resolvedPIDs)
        }
    }

    private func stopCaptureAsync() {
        lifecycleQueue.async { [weak self] in
            self?.stopCaptureOnLifecycleQueue()
        }
    }

    private func resolvePIDs(displayBundleID: String, captureBundleIDs: [String]) -> [pid_t] {
        let displayApps = NSRunningApplication.runningApplications(withBundleIdentifier: displayBundleID)
        let displayNames = Set(displayApps.compactMap(\.localizedName))
        let displayBundlePaths = Set(displayApps.compactMap(displayBundlePath(for:)))

        let bundleIDs = Array(
            Set(captureBundleIDs + [displayBundleID])
        ).sorted()

        var pids = Set<pid_t>()
        for bundleID in bundleIDs {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            let requireDisplayAppTie = bundleID != displayBundleID && runningApps.count > 1
            for app in runningApps {
                guard shouldInclude(
                    app: app,
                    requireDisplayAppTie: requireDisplayAppTie,
                    displayNames: displayNames,
                    displayBundlePaths: displayBundlePaths
                ) else { continue }
                pids.insert(app.processIdentifier)
            }
        }

        if pids.isEmpty {
            return NSRunningApplication
                .runningApplications(withBundleIdentifier: displayBundleID)
                .map(\.processIdentifier)
                .sorted()
        }

        return pids.sorted()
    }

    private func shouldInclude(
        app: NSRunningApplication,
        requireDisplayAppTie: Bool,
        displayNames: Set<String>,
        displayBundlePaths: Set<String>
    ) -> Bool {
        guard requireDisplayAppTie else { return true }
        if belongsToDisplayApplication(app, displayBundlePaths: displayBundlePaths) {
            return true
        }
        guard let localizedName = app.localizedName, !displayNames.isEmpty else { return false }
        return displayNames.contains { localizedName.localizedCaseInsensitiveContains($0) }
    }

    private func belongsToDisplayApplication(
        _ app: NSRunningApplication,
        displayBundlePaths: Set<String>
    ) -> Bool {
        guard !displayBundlePaths.isEmpty else { return false }

        if let bundlePath = displayBundlePath(for: app),
           displayBundlePaths.contains(where: { pathContainsApp($0, candidatePath: bundlePath) }) {
            return true
        }

        guard let executablePath = executablePath(forPID: app.processIdentifier) else { return false }
        return displayBundlePaths.contains { pathContainsApp($0, candidatePath: executablePath) }
    }

    private func displayBundlePath(for app: NSRunningApplication) -> String? {
        if let bundlePath = app.bundleURL?.standardizedFileURL.path {
            return bundlePath
        }
        guard let executablePath = executablePath(forPID: app.processIdentifier) else { return nil }
        return outermostAppBundlePath(containing: executablePath)
    }

    private func executablePath(forPID pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).standardizedFileURL.path
    }

    private func outermostAppBundlePath(containing executablePath: String) -> String? {
        let normalizedPath = URL(fileURLWithPath: executablePath).standardizedFileURL.path
        let components = normalizedPath.split(separator: "/")
        guard let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return "/" + components[...appIndex].joined(separator: "/")
    }

    private func pathContainsApp(_ appPath: String, candidatePath: String) -> Bool {
        let normalizedAppPath = URL(fileURLWithPath: appPath).standardizedFileURL.path
        let normalizedCandidatePath = URL(fileURLWithPath: candidatePath).standardizedFileURL.path
        return normalizedCandidatePath == normalizedAppPath
            || normalizedCandidatePath.hasPrefix(normalizedAppPath + "/")
    }

    // MARK: - Capture lifecycle

    @available(macOS 14.2, *)
    private func startCaptureOnLifecycleQueue(pids: [pid_t]) {
        dispatchPrecondition(condition: .onQueue(lifecycleQueue))
        if ioProcID != nil, pids == currentPIDs { return }
        if captureIsConfigured {
            stopCaptureOnLifecycleQueue()
        }

        let attachedProcesses = pids.compactMap { pid -> (pid: pid_t, objectID: AudioObjectID)? in
            guard let objectID = translatePIDToAudioObject(pid: pid) else {
                NSLog("[AudioCaptureManager] Failed to translate PID \(pid) to AudioObjectID")
                return nil
            }
            return (pid: pid, objectID: objectID)
        }
        guard !attachedProcesses.isEmpty else {
            currentPIDs.removeAll(keepingCapacity: true)
            return
        }
        let resolvedProcessObjectIDs = attachedProcesses.map(\.objectID)
        currentPIDs = attachedProcesses.map(\.pid)

        let tapDescription = CATapDescription(monoMixdownOfProcesses: resolvedProcessObjectIDs)
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true
        tapDescription.isExclusive = false

        var newTapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard tapStatus == noErr, newTapID != kAudioObjectUnknown else {
            NSLog("[AudioCaptureManager] AudioHardwareCreateProcessTap failed: \(tapStatus)")
            currentPIDs.removeAll(keepingCapacity: true)
            return
        }
        tapObjectID = newTapID

        guard let tapUID = getAudioObjectStringProperty(
            objectID: tapObjectID,
            selector: kAudioTapPropertyUID
        ) else {
            NSLog("[AudioCaptureManager] Failed to read tap UID")
            currentPIDs.removeAll(keepingCapacity: true)
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
        guard fmtStatus == noErr else {
            NSLog("[AudioCaptureManager] Failed to read tap format: \(fmtStatus)")
            currentPIDs.removeAll(keepingCapacity: true)
            cleanupTap()
            return
        }
        guard validateTapFormat(streamFormat) else {
            NSLog("[AudioCaptureManager] Unsupported tap format: \(streamFormat)")
            currentPIDs.removeAll(keepingCapacity: true)
            cleanupTap()
            return
        }
        if streamFormat.mSampleRate > 0 {
            sampleRate = streamFormat.mSampleRate
        }
        computeBandRanges(sampleRate: sampleRate)

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
            currentPIDs.removeAll(keepingCapacity: true)
            cleanupTap()
            return
        }
        aggregateDeviceID = newAggID

        var newIOProc: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
            &newIOProc, aggregateDeviceID, ioQueue
        ) { [weak self] _, inInputData, _, _, _ in
            self?.handleInputBuffer(inInputData)
        }
        guard ioStatus == noErr, let ioProc = newIOProc else {
            NSLog("[AudioCaptureManager] AudioDeviceCreateIOProcIDWithBlock failed: \(ioStatus)")
            currentPIDs.removeAll(keepingCapacity: true)
            cleanupAggregate()
            cleanupTap()
            return
        }
        ioProcID = ioProc

        let startStatus = AudioDeviceStart(aggregateDeviceID, ioProc)
        guard startStatus == noErr else {
            NSLog("[AudioCaptureManager] AudioDeviceStart failed: \(startStatus)")
            destroyIOProc(ioProc)
            ioProcID = nil
            currentPIDs.removeAll(keepingCapacity: true)
            cleanupAggregate()
            cleanupTap()
            return
        }

        startFFTTimer()
        setCapturing(true)
    }

    private var captureIsConfigured: Bool {
        ioProcID != nil || aggregateDeviceID != 0 || tapObjectID != kAudioObjectUnknown
    }

    private func syncOnLifecycleQueue(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: Self.lifecycleQueueKey) != nil {
            work()
        } else {
            lifecycleQueue.sync(execute: work)
        }
    }

    private func stopCaptureOnLifecycleQueue() {
        dispatchPrecondition(condition: .onQueue(lifecycleQueue))
        guard captureIsConfigured else { return }
        stopFFTTimer()
        teardownCapture()
        currentPIDs.removeAll(keepingCapacity: true)
        syncOnFFTQueue {
            resetProcessingState()
        }
        let zeros = [Float](repeating: 0, count: Self.barCount)
        setCapturing(false)
        publishLevels(zeros)
    }

    private func resetProcessingState() {
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

    private func teardownCapture() {
        if aggregateDeviceID != 0, let proc = ioProcID {
            let stopStatus = AudioDeviceStop(aggregateDeviceID, proc)
            if stopStatus != noErr {
                NSLog("[AudioCaptureManager] AudioDeviceStop failed during teardown: \(stopStatus)")
            }
            destroyIOProc(proc)
        }
        ioProcID = nil
        cleanupAggregate()
        cleanupTap()
    }

    private func destroyIOProc(_ proc: AudioDeviceIOProcID) {
        guard aggregateDeviceID != 0 else { return }
        let status = AudioDeviceDestroyIOProcID(aggregateDeviceID, proc)
        if status != noErr {
            NSLog("[AudioCaptureManager] AudioDeviceDestroyIOProcID failed: \(status)")
        }
    }

    private func cleanupAggregate() {
        if aggregateDeviceID != 0 {
            let status = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if status == noErr || Self.allowedAlreadyDestroyedStatuses.contains(status) {
                aggregateDeviceID = 0
            } else {
                NSLog("[AudioCaptureManager] AudioHardwareDestroyAggregateDevice failed: \(status)")
            }
        }
    }

    private func cleanupTap() {
        guard tapObjectID != kAudioObjectUnknown else { return }
        if #available(macOS 14.2, *) {
            let status = AudioHardwareDestroyProcessTap(tapObjectID)
            if status == noErr || Self.allowedAlreadyDestroyedStatuses.contains(status) {
                tapObjectID = kAudioObjectUnknown
            } else {
                NSLog("[AudioCaptureManager] AudioHardwareDestroyProcessTap failed: \(status)")
            }
        } else {
            tapObjectID = kAudioObjectUnknown
        }
    }

    private func setCapturing(_ capturing: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCapturing != capturing else { return }
            self.isCapturing = capturing
        }
    }

    // MARK: - IO proc

    private func handleInputBuffer(_ bufferList: UnsafePointer<AudioBufferList>) {
        let mutableBL = UnsafeMutablePointer(mutating: bufferList)
        let abl = UnsafeMutableAudioBufferListPointer(mutableBL)
        guard let first = abl.first, let rawData = first.mData else { return }
        let expectedBytesPerFrame = UInt32(MemoryLayout<Float>.size)
        guard first.mNumberChannels == 1,
              first.mDataByteSize % expectedBytesPerFrame == 0 else { return }
        let frameCount = Int(first.mDataByteSize / expectedBytesPerFrame)
        guard frameCount > 0 else { return }
        let src = rawData.assumingMemoryBound(to: Float.self)

        ringLock.lock()
        defer { ringLock.unlock() }

        let cap = Self.ringCapacity
        if frameCount >= cap {
            let newestFrames = src.advanced(by: frameCount - cap)
            memcpy(ringBuffer, newestFrames, cap * MemoryLayout<Float>.size)
            ringWrite = 0
            return
        }
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
    }

    // MARK: - FFT loop

    private func startFFTTimer() {
        let timer = DispatchSource.makeTimerSource(queue: fftQueue)
        timer.schedule(
            deadline: .now(),
            repeating: .milliseconds(Self.fftIntervalMilliseconds),
            leeway: .milliseconds(Self.fftLeewayMilliseconds)
        )
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
        copyLatestSamples(count: n)

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
            let decayed = smoothed[i] * 0.86
            let next = target > decayed ? (decayed + (target - decayed) * 0.58) : decayed
            smoothed[i] = next
            let clipped = max(0, min(1, next))
            barsBuf[i] = clipped
            let delta = abs(clipped - lastPublishedBuf[i])
            if delta > maxDelta { maxDelta = delta }
        }

        // Skip main-thread delivery when nothing perceptible changed.
        guard maxDelta > 1e-4 else { return }
        for i in 0..<Self.barCount {
            lastPublishedBuf[i] = barsBuf[i]
        }
        publishLevels(barsBuf.map { $0 })
    }

    private func copyLatestSamples(count: Int) {
        ringLock.lock()
        defer { ringLock.unlock() }

        let cap = Self.ringCapacity
        let end = ringWrite
        let start = (end - count + cap) % cap
        samplesBuf.withUnsafeMutableBufferPointer { dst in
            guard let base = dst.baseAddress else { return }
            if start + count <= cap {
                memcpy(base, ringBuffer.advanced(by: start), count * MemoryLayout<Float>.size)
            } else {
                let firstCount = cap - start
                memcpy(base, ringBuffer.advanced(by: start), firstCount * MemoryLayout<Float>.size)
                memcpy(
                    base.advanced(by: firstCount),
                    ringBuffer,
                    (count - firstCount) * MemoryLayout<Float>.size
                )
            }
        }
    }

    private func publishLevels(_ values: [Float]) {
        levelsConsumerLock.lock()
        latestLevels = values
        let consumers = levelsConsumers.allObjects.compactMap { $0 as? AudioCaptureLevelsConsumer }
        levelsConsumerLock.unlock()
        guard !consumers.isEmpty else { return }

        let deliverLevels = { [weak self] in
            guard let self else { return }
            for consumer in consumers {
                consumer.audioCaptureManager(self, didProduceLevels: values)
            }
        }

        if Thread.isMainThread {
            deliverLevels()
        } else {
            DispatchQueue.main.async(execute: deliverLevels)
        }
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
            pinks.append(Float(Self.pinkCompensationSlopePerOctave * log2(centerHz / Self.referenceHz)))
        }
        bandRanges = ranges
        pinkCompensationDB = pinks
    }

    private func validateTapFormat(_ format: AudioStreamBasicDescription) -> Bool {
        let floatPCMFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        return format.mFormatID == kAudioFormatLinearPCM
            && (format.mFormatFlags & floatPCMFlags) == floatPCMFlags
            && (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
            && format.mChannelsPerFrame == 1
            && format.mBytesPerFrame == UInt32(MemoryLayout<Float>.size)
            && format.mBitsPerChannel == UInt32(MemoryLayout<Float>.size * 8)
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
