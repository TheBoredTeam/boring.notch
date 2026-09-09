//
//  AudioProcessObserver.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import CoreAudio
import Foundation

/// Tracks audio helpers that may start after their parent app begins playback.
final class AudioProcessObserver {
    private let listener: AudioObjectPropertyListenerBlock
    private let isObserving: Bool

    init(onChange: @escaping () -> Void) {
        listener = { _, _ in onChange() }
        var address = Self.processListAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
        isObserving = status == noErr
        if status != noErr {
            Log.music.error("Failed to observe audio process list: \(status)")
        }
    }

    deinit {
        guard isObserving else { return }
        var address = Self.processListAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
    }

    static func processPIDs(
        matching bundleIDs: Set<String>,
        belongsToDisplayApp: (pid_t) -> Bool
    ) -> Set<pid_t> {
        guard !bundleIDs.isEmpty else { return [] }
        var address = processListAddress
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        )
        guard sizeStatus == noErr, size >= UInt32(MemoryLayout<AudioObjectID>.size) else { return [] }

        var objectIDs = [AudioObjectID](
            repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        let listStatus = objectIDs.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return kAudioHardwareBadPropertySizeError }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, base
            )
        }
        guard listStatus == noErr else { return [] }

        var pids = Set<pid_t>()
        for objectID in objectIDs {
            guard let bundleID = bundleIdentifier(for: objectID),
                  let pid = processID(for: objectID),
                  isCaptureTarget(
                    bundleIdentifier: bundleID,
                    bundleIDs: bundleIDs,
                    belongsToDisplayApp: belongsToDisplayApp(pid)
                  ) else { continue }
            pids.insert(pid)
        }
        return pids
    }

    static func isCaptureTarget(
        bundleIdentifier: String,
        bundleIDs: Set<String>,
        belongsToDisplayApp: @autoclosure () -> Bool
    ) -> Bool {
        guard !bundleIdentifier.isEmpty, !bundleIDs.isEmpty else { return false }
        let candidate = bundleIdentifier.lowercased()
        // WebKit is shared by many apps; its icon is not proof of ownership.
        if candidate.hasPrefix("com.apple.webkit.") {
            return belongsToDisplayApp()
        }
        let candidateFamily = helperFamily(for: candidate)
        return bundleIDs.contains { target in
            !target.isEmpty && helperFamily(for: target.lowercased()) == candidateFamily
        }
    }

    private static func helperFamily(for bundleIdentifier: String) -> String {
        let components = bundleIdentifier.components(separatedBy: ".")
        guard let helperIndex = components.firstIndex(of: "helper"), helperIndex > 0 else {
            return bundleIdentifier
        }
        return components[..<helperIndex].joined(separator: ".")
    }

    private static var processListAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func bundleIdentifier(for objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var bundleID: CFString?
        let status = withUnsafeMutablePointer(to: &bundleID) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let bundleID else { return nil }
        return bundleID as String
    }

    private static func processID(for objectID: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &pid)
        guard status == noErr, pid > 0 else { return nil }
        return pid
    }
}
