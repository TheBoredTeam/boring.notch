//
//  PrivacyActivityManager.swift
//  boringNotch
//

import AppKit
import Combine
import CoreAudio
import CoreMediaIO
import Defaults
import Foundation

/// Tells the user when the microphone or camera starts and stops being used.
///
/// Detection is device level and entirely event driven: CoreAudio's
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default input device, and
/// CoreMediaIO's equivalent on each camera. Both were measured to fire reliably on start and
/// on stop, cross-checked against a poll that reported no missed transitions. Nothing here
/// polls, and nothing here opens a capture session, so no permission prompt is triggered:
/// these are device properties, not recording.
///
/// ## Limitations
/// - **The camera cannot be attributed to an app.** CoreMediaIO exposes no per-client API —
///   its only bundle-identifier properties describe plug-ins, not the process using the
///   device — so the camera is reported as in use, without a name. Naming it would take
///   private API, which this deliberately does not do.
/// - Microphone attribution is best effort. It comes from CoreAudio's process objects, which
///   report a bundle identifier per recorder; helper processes are folded onto their parent
///   app and system services are filtered out. A recorder with no bundle identifier still
///   counts as microphone use but cannot be named.
/// - System services that listen on their own (Siri, dictation) are deliberately not
///   surfaced. macOS shows its own indicator for those, and reporting them would read as a
///   false alarm.
/// - Detection follows the *default* input device. Audio captured from a non-default device
///   is not observed.
@MainActor
final class PrivacyActivityManager: ObservableObject {
    nonisolated static let shared = PrivacyActivityManager()

    /// What is in use right now, for the opened notch to display.
    @Published private(set) var usage = PrivacyUsage()

    /// The transition currently being announced in the closed notch, if any.
    @Published private(set) var announcement: Announcement?

    struct Announcement: Equatable {
        var resource: PrivacyResource
        var isStarting: Bool
        var appName: String?
    }

    private var detector = PrivacyTransitionDetector()
    private var cancellables = Set<AnyCancellable>()
    private var isRunning = false

    // CoreAudio
    private var inputDevice = AudioObjectID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?

    // CoreMediaIO
    private var cameraDevices: [CMIOObjectID] = []
    private var cameraListeners: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]
    private var cameraListListener: CMIOObjectPropertyListenerBlock?

    private var announcementTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?

    nonisolated private init() {}

    // MARK: - Lifecycle

    func start() {
        for key in [Defaults.Keys.microphoneActivity, Defaults.Keys.cameraActivity] {
            Defaults.publisher(key, options: [])
                .sink { [weak self] _ in Task { @MainActor in self?.applyEnabledState() } }
                .store(in: &cancellables)
        }
        applyEnabledState()
    }

    func stop() {
        cancellables.removeAll()
        stopObserving()
    }

    private var isEnabled: Bool {
        Defaults[.microphoneActivity] || Defaults[.cameraActivity]
    }

    private func applyEnabledState() {
        if isEnabled {
            startObserving()
            // A setting switched on mid-session should reflect reality at once rather than
            // waiting for the next transition.
            refresh(announce: false)
        } else {
            stopObserving()
        }
    }

    private func startObserving() {
        guard !isRunning else { return }
        isRunning = true

        attachDefaultInputDeviceListener()
        attachMicrophoneListener()
        attachCameraListeners()

        NSLog("🔒 Privacy monitoring started (mic device=\(inputDevice), cameras=\(cameraDevices.count))")
    }

    private func stopObserving() {
        guard isRunning else { return }
        isRunning = false

        detachMicrophoneListener()
        detachDefaultInputDeviceListener()
        detachCameraListeners()

        announcementTask?.cancel()
        announcementTask = nil
        settleTask?.cancel()
        settleTask = nil
        announcement = nil
        usage = PrivacyUsage()
        detector = PrivacyTransitionDetector()
        hideActivity()
    }

    // MARK: - CoreAudio

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultInputDevice() -> AudioObjectID {
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { return AudioObjectID(kAudioObjectUnknown) }
        return device
    }

    private static func isDeviceRunningSomewhere(_ device: AudioObjectID) -> Bool {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return false }
        var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return false }
        return value != 0
    }

    /// Bundle identifiers of every process currently recording, unfiltered.
    private static func recordingBundleIdentifiers() -> [String] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var listAddress = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &size) == noErr,
              size > 0
        else { return [] }

        var objects = [AudioObjectID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &listAddress, 0, nil, &size, &objects) == noErr
        else { return [] }

        return objects.compactMap { object -> String? in
            var runningAddress = Self.address(kAudioProcessPropertyIsRunningInput)
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(
                object, &runningAddress, 0, nil, &runningSize, &running) == noErr,
                running != 0
            else { return nil }

            var bundleAddress = Self.address(kAudioProcessPropertyBundleID)
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(
                object, &bundleAddress, 0, nil, &bundleSize, &bundle) == noErr,
                let bundle
            else { return "" }
            return bundle.takeRetainedValue() as String
        }
    }

    private func attachDefaultInputDeviceListener() {
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                // Switching to AirPods swaps the device out from under the listener, so the
                // listener has to move with it.
                self?.attachMicrophoneListener()
                self?.refresh(announce: true)
            }
        }
        defaultDeviceListener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    }

    private func detachDefaultInputDeviceListener() {
        guard let defaultDeviceListener else { return }
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, defaultDeviceListener)
        self.defaultDeviceListener = nil
    }

    private func attachMicrophoneListener() {
        detachMicrophoneListener()

        let device = Self.defaultInputDevice()
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        inputDevice = device

        var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh(announce: true) }
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(device, &address, .main, block)
    }

    private func detachMicrophoneListener() {
        guard let deviceListener, inputDevice != AudioObjectID(kAudioObjectUnknown) else { return }
        var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        AudioObjectRemovePropertyListenerBlock(inputDevice, &address, .main, deviceListener)
        self.deviceListener = nil
    }

    // MARK: - CoreMediaIO

    private static func cmioAddress(_ selector: CMIOObjectPropertySelector)
        -> CMIOObjectPropertyAddress
    {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func cameraDeviceIDs() -> [CMIOObjectID] {
        var address = Self.cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0
        else { return [] }

        var devices = [CMIOObjectID](
            repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == noErr
        else { return [] }
        return devices
    }

    private static func isCameraRunning(_ device: CMIOObjectID) -> Bool {
        var address = Self.cmioAddress(
            CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        var value: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &value) == noErr
        else { return false }
        return value != 0
    }

    private func attachCameraListeners() {
        detachCameraListeners()

        cameraDevices = Self.cameraDeviceIDs()
        for device in cameraDevices {
            var address = Self.cmioAddress(
                CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.refresh(announce: true) }
            }
            cameraListeners[device] = block
            CMIOObjectAddPropertyListenerBlock(device, &address, .main, block)
        }

        // Cameras come and go — a USB webcam, or Continuity Camera appearing when an iPhone
        // is nearby — so the set itself has to be watched too.
        var listAddress = Self.cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let listBlock: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.attachCameraListeners()
                self?.refresh(announce: true)
            }
        }
        cameraListListener = listBlock
        CMIOObjectAddPropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject), &listAddress, .main, listBlock)
    }

    private func detachCameraListeners() {
        for (device, block) in cameraListeners {
            var address = Self.cmioAddress(
                CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            CMIOObjectRemovePropertyListenerBlock(device, &address, .main, block)
        }
        cameraListeners.removeAll()

        if let cameraListListener {
            var listAddress = Self.cmioAddress(
                CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
            CMIOObjectRemovePropertyListenerBlock(
                CMIOObjectID(kCMIOObjectSystemObject), &listAddress, .main, cameraListListener)
            self.cameraListListener = nil
        }
        cameraDevices.removeAll()
    }

    // MARK: - State

    /// How long the hardware state must hold before it is worth telling the user about.
    ///
    /// Apps flap the device on the way up and down — QuickTime was measured stopping,
    /// restarting and stopping again inside 85ms as it tore a recording down. Announcing
    /// each edge would flicker the notch, so the state is allowed to settle first. A
    /// blip shorter than this is not something the user needs to be told about at all.
    private static let settleInterval: Duration = .milliseconds(500)

    private func currentUsage() -> PrivacyUsage {
        let micActive = Defaults[.microphoneActivity]
            && Self.isDeviceRunningSomewhere(inputDevice)
        let cameraActive = Defaults[.cameraActivity]
            && cameraDevices.contains(where: Self.isCameraRunning)

        var current = PrivacyUsage(
            microphoneActive: micActive,
            cameraActive: cameraActive,
            microphoneApps: micActive ? resolveMicrophoneApps() : []
        )

        // Attribution can lag the device flag by a moment; keeping the previously known app
        // avoids the name flickering away mid-use.
        if micActive, current.microphoneApps.isEmpty, !usage.microphoneApps.isEmpty {
            current.microphoneApps = usage.microphoneApps
        }
        return current
    }

    /// Re-read the world. The opened notch updates at once; announcements wait for the
    /// state to settle.
    private func refresh(announce: Bool) {
        guard isRunning else { return }

        let current = currentUsage()
        usage = current

        guard announce else {
            // Seed the detector so enabling the feature mid-use does not read as a start.
            _ = detector.update(current)
            return
        }

        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleInterval)
            guard let self, !Task.isCancelled, self.isRunning else { return }
            self.announceSettledState()
        }
    }

    /// Announce whatever actually changed once the flapping has stopped.
    private func announceSettledState() {
        let settled = currentUsage()
        usage = settled
        for event in detector.update(settled) {
            announceTransition(event, usage: settled)
        }
    }

    /// Turn the raw recorder list into apps a person would recognise.
    private func resolveMicrophoneApps() -> [PrivacyApp] {
        PrivacyAttribution.normalize(Self.recordingBundleIdentifiers())
            .compactMap { bundleID in
                // Only apps with a real presence get named. This is what keeps background
                // daemons that slipped past the exclusion list from being reported.
                guard let app = NSRunningApplication
                    .runningApplications(withBundleIdentifier: bundleID)
                    .first(where: { $0.activationPolicy != .prohibited })
                else { return nil }
                return PrivacyApp(
                    bundleIdentifier: bundleID,
                    name: app.localizedName ?? bundleID
                )
            }
    }

    private func announceTransition(_ event: PrivacyTransitionDetector.Event, usage: PrivacyUsage) {
        let resource: PrivacyResource
        let isStarting: Bool
        switch event {
        case .started(let value): resource = value; isStarting = true
        case .stopped(let value): resource = value; isStarting = false
        }

        // The camera has no attributable app by design, so it never carries a name.
        let appName = resource == .microphone ? usage.microphoneApps.first?.name : nil

        NSLog("🔒 \(resource.rawValue) \(isStarting ? "started" : "stopped") \(appName.map { "— \($0)" } ?? "")")

        announcement = Announcement(resource: resource, isStarting: isStarting, appName: appName)

        // Transient by design: a blip at each end. While the resource stays in use the
        // opened notch is where that is visible, so the closed notch stays clean even
        // through a long call.
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .privacy)

        announcementTask?.cancel()
        announcementTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !Task.isCancelled else { return }
            self.announcement = nil
        }
    }

    private func hideActivity() {
        let coordinator = BoringViewCoordinator.shared
        if coordinator.currentView == .privacy {
            coordinator.currentView = .home
        }
        guard coordinator.expandingView.show, coordinator.expandingView.type == .privacy else { return }
        coordinator.toggleExpandingView(status: false, type: .privacy)
    }

    /// Whether the opened notch should offer a Privacy section.
    var hasVisibleActivity: Bool { usage.isAnythingActive || announcement != nil }
}
