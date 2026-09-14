//
//  PrivacyActivityState.swift
//  boringNotch
//

import Foundation

/// A resource whose use is worth telling the user about.
enum PrivacyResource: String, Equatable, CaseIterable {
    case microphone
    case camera
}

/// An app we were able to hold responsible for using a resource.
struct PrivacyApp: Identifiable, Equatable {
    var bundleIdentifier: String
    var name: String

    var id: String { bundleIdentifier }
}

/// What is in use right now.
struct PrivacyUsage: Equatable {
    var microphoneActive: Bool = false
    var cameraActive: Bool = false
    /// Best effort, and microphone-only: macOS exposes no per-client API for the camera.
    var microphoneApps: [PrivacyApp] = []

    var isAnythingActive: Bool { microphoneActive || cameraActive }

    var activeResources: [PrivacyResource] {
        var result: [PrivacyResource] = []
        if microphoneActive { result.append(.microphone) }
        if cameraActive { result.append(.camera) }
        return result
    }
}

/// Works out which processes are worth naming as the cause of microphone use.
///
/// The raw CoreAudio process list is not presentable on its own: it is full of system
/// services that engage the microphone alongside a real app, and of helper processes whose
/// bundle identifier is not the app the user recognises.
enum PrivacyAttribution {
    /// System services that turn the microphone on without the user starting anything —
    /// Siri and dictation listening, Control Center, accessibility. macOS shows its own
    /// indicator for these, and surfacing them would read as a false alarm.
    ///
    /// Measured on a real machine: `com.apple.CoreSpeech` appears as a recorder whenever
    /// another app starts recording, and lingers briefly after it stops.
    static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.CoreSpeech",
        "com.apple.Siri",
        "com.apple.SiriNCService",
        "com.apple.siriactionsd",
        "com.apple.assistantd",
        "com.apple.assistant_service",
        "com.apple.audiomxd",
        "com.apple.controlcenter",
        "com.apple.accessibility.heard",
        "com.apple.universalaccessd",
        "com.apple.avconferenced",
        "com.apple.TelephonyUtilities",
        "com.apple.loginwindow",
        "com.apple.mediaremoted",
        "com.apple.cmio.ContinuityCaptureAgent",
    ]

    static func isExcluded(_ bundleIdentifier: String) -> Bool {
        excludedBundleIdentifiers.contains(bundleIdentifier)
    }

    /// Collapse the raw recorder list onto the apps a person would recognise.
    ///
    /// Helper processes are folded onto their parent app (`com.google.Chrome.helper` is
    /// Chrome as far as anyone is concerned), system services are dropped, and duplicates
    /// are removed while keeping the original order so the first recorder stays first.
    static func normalize(_ bundleIdentifiers: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in bundleIdentifiers {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            // Some audio processes report no bundle identifier at all; there is nothing to
            // name them with, so they are counted as use but never attributed.
            guard !trimmed.isEmpty else { continue }
            let normalized = normalizeBundleIdentifier(trimmed)
            guard !isExcluded(normalized), !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }
        return result
    }
}

/// Turns a stream of "what is in use now" readings into start and stop events.
///
/// The point is that a resource staying on must not keep producing events: the notch should
/// blip once when recording starts and once when it stops, and the opened notch is where the
/// still-active state is visible in between.
struct PrivacyTransitionDetector {
    enum Event: Equatable {
        case started(PrivacyResource)
        case stopped(PrivacyResource)
    }

    private var previous = PrivacyUsage()

    /// Feed the latest reading in and get back only what actually changed.
    mutating func update(_ current: PrivacyUsage) -> [Event] {
        var events: [Event] = []

        if current.microphoneActive != previous.microphoneActive {
            events.append(current.microphoneActive ? .started(.microphone) : .stopped(.microphone))
        }
        if current.cameraActive != previous.cameraActive {
            events.append(current.cameraActive ? .started(.camera) : .stopped(.camera))
        }

        previous = current
        return events
    }

    /// Whether anything is currently in use, per the last reading.
    var isAnythingActive: Bool { previous.isAnythingActive }
}
