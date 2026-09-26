//
//  CameraSessionEngine.swift
//  boringNotch
//
//  Created by Alexander on 2026-09-16.
//

import AVFoundation
import AppKit
import Foundation
import os
import os.lock

struct CameraDevice: Identifiable, Equatable {
    /// Coarse hardware class. The raw value doubles as the Automatic preference order.
    enum Kind: Int, Equatable {
        case builtIn = 0
        case continuity = 1
        case deskView = 2
        case external = 3
    }

    let id: String
    let name: String
    let kind: Kind
}

/// The user's persisted choice. Device discovery never rewrites it; only an
/// explicit selection does.
enum CameraSelection: Equatable, Hashable {
    case automatic
    case device(String)
}

enum CameraSessionEvent: @unchecked Sendable {
    case authorization(AVAuthorizationStatus)
    case devices([CameraDevice])
    case started(session: AVCaptureSession, device: CameraDevice)
    /// macOS temporarily suspended the capture session. User intent is unchanged.
    case interrupted
    case stopped
    case failed(String)
}

protocol CameraSessionEngine: AnyObject {
    var eventHandler: (@MainActor @Sendable (CameraSessionEvent) -> Void)? { get set }

    func refresh()
    func requestAccess()
    func start(selection: CameraSelection)
    func stop()
    func shutdown()
}

func preferredCamera(from devices: [CameraDevice], selection: CameraSelection) -> CameraDevice? {
    switch selection {
    case .device(let id):
        return devices.first { $0.id == id }
    case .automatic:
        return devices.min { ($0.kind.rawValue, $0.id) < ($1.kind.rawValue, $1.id) }
    }
}

/// Owns AVFoundation objects and serializes all session work away from the UI.
private final class CameraEngineState: @unchecked Sendable {
    var captureSession: AVCaptureSession?
    var activeInput: AVCaptureDeviceInput?
    var activeDeviceID: String?
    var selection: CameraSelection = .automatic
    var shouldRun = false
    var lastPublishedDevices: [CameraDevice]?
    let callbacks = OSAllocatedUnfairLock(initialState: CameraEngineCallbacks())
}

private struct CameraEngineCallbacks: Sendable {
    var isShutDown = false
    var handler: (@MainActor @Sendable (CameraSessionEvent) -> Void)?
}

final class AVCaptureSessionEngine: NSObject, CameraSessionEngine {
    var eventHandler: (@MainActor @Sendable (CameraSessionEvent) -> Void)? {
        get { state.callbacks.withLock { $0.handler } }
        set {
            state.callbacks.withLock {
                $0.handler = newValue
            }
        }
    }

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "boringNotch",
        category: "camera"
    )

    private let sessionQueue = DispatchQueue(
        label: "BoringNotch.CameraSessionEngine",
        qos: .userInitiated
    )
    private let notificationCenter: NotificationCenter
    private let state = CameraEngineState()

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        super.init()

        notificationCenter.addObserver(
            self,
            selector: #selector(deviceWasDisconnected),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(deviceWasConnected),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        shutdown()
    }

    // MARK: - Public API (thread-safe, all work serialized on sessionQueue)

    func refresh() {
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }) else { return }
            Self.publishAuthorization(state: state)
            Self.reconcile(state: state)
        }
    }

    func requestAccess() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let state = state
        let queue = sessionQueue
        Self.publish(.authorization(status), state: state)

        guard status == .notDetermined else {
            if status == .authorized {
                refresh()
            }
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { granted in
            Self.publish(.authorization(granted ? .authorized : .denied), state: state)
            if granted {
                queue.async {
                    guard !state.callbacks.withLock({ $0.isShutDown }) else { return }
                    Self.publishAuthorization(state: state)
                    Self.reconcile(state: state)
                }
            }
        }
    }

    func start(selection: CameraSelection) {
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }) else { return }
            state.shouldRun = true
            state.selection = selection
            Self.reconcile(state: state)
        }
    }

    func stop() {
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }) else { return }
            state.shouldRun = false
            // Full teardown, not just stopRunning(): a configured-but-idle
            // session that macOS paused (no attached preview layer) never
            // re-streams when startRunning() is called again, which broke
            // second starts and starts after closing the notch.
            Self.teardownSession(state: state)
            Self.publish(.stopped, state: state)
        }
    }

    func shutdown() {
        state.callbacks.withLock {
            $0.isShutDown = true
            $0.handler = nil
        }
        sessionQueue.sync {
            state.shouldRun = false
            Self.teardownSession(state: state)
        }
    }

    // MARK: - Reconciliation (sessionQueue only)

    /// Single entry point that enforces the desired session state for the
    /// current selection + intent: discover, publish the list, and make the
    /// session match. Idempotent; never starts capture unless `shouldRun`.
    private static func reconcile(state: CameraEngineState) {
        let devices = discoveredDevices()
        if devices != state.lastPublishedDevices {
            state.lastPublishedDevices = devices
            publish(.devices(devices), state: state)
        }

        guard state.shouldRun else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            publishAuthorization(state: state)
            return
        }

        guard let preferred = preferredCamera(from: devices, selection: state.selection),
              let device = AVCaptureDevice(uniqueID: preferred.id) else {
            // No cameras at all, or an explicitly selected camera is absent.
            // The selection and the intent are preserved; a later device event
            // retries. Never silently fall back to a different camera here.
            teardownSession(state: state)
            publish(.stopped, state: state)
            return
        }

        attachCamera(device: device, preferred: preferred, state: state)
    }

    /// Reuse the configured session whenever possible; recreate it only as a
    /// recovery fallback.
    private static func attachCamera(device: AVCaptureDevice, preferred: CameraDevice, state: CameraEngineState) {
        // Fast path: the requested camera is already attached.
        if let session = state.captureSession, let input = state.activeInput,
           input.device.uniqueID == device.uniqueID {
            if session.isRunning {
                publish(.started(session: session, device: preferred), state: state)
                return
            }
            session.startRunning()
            if session.isRunning {
                publish(.started(session: session, device: preferred), state: state)
            } else {
                rebuildSession(for: device, preferred: preferred, state: state)
            }
            return
        }

        // Camera switch: replace the video input on the live session and
        // preserve both the session and its running state. Only attempted
        // while the session is actively streaming; a stopped one is rebuilt
        // below (a paused session cannot be reliably revived).
        if let session = state.captureSession, session.isRunning,
           swapInput(to: device, on: session, state: state), session.isRunning {
            publish(.started(session: session, device: preferred), state: state)
            return
        }

        rebuildSession(for: device, preferred: preferred, state: state)
    }

    private static func swapInput(to device: AVCaptureDevice, on session: AVCaptureSession, state: CameraEngineState) -> Bool {
        guard let newInput = try? AVCaptureDeviceInput(device: device) else { return false }

        session.beginConfiguration()
        if let oldInput = state.activeInput {
            session.removeInput(oldInput)
        }
        let added = session.canAddInput(newInput)
        if added {
            session.addInput(newInput)
        }
        session.commitConfiguration()

        guard added else { return false }
        state.activeInput = newInput
        state.activeDeviceID = device.uniqueID
        return true
    }

    private static func rebuildSession(for device: AVCaptureDevice, preferred: CameraDevice, state: CameraEngineState) {
        teardownSession(state: state)

        let session = AVCaptureSession()
        session.beginConfiguration()
        // The mirror preview is a fixed 142pt square on a retina panel.
        // `.medium` lets the hardware negotiate the smallest frame it offers
        // (typically 480×360) instead of pinning an exact preset, which keeps
        // ISP/power draw low for the long periods the mirror stays open and
        // works on cameras that reject fixed-size presets.
        if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                throw CameraSessionError.cannotAddInput
            }
            session.addInput(input)
            session.commitConfiguration()
        } catch {
            publish(.failed(error.localizedDescription), state: state)
            return
        }

        session.startRunning()
        if session.isRunning {
            state.captureSession = session
            state.activeInput = session.inputs.first as? AVCaptureDeviceInput
            state.activeDeviceID = device.uniqueID
            publish(.started(session: session, device: preferred), state: state)
        } else {
            publish(.failed("The camera could not be started"), state: state)
        }
    }

    private static func teardownSession(state: CameraEngineState) {
        if let session = state.captureSession {
            if session.isRunning {
                session.stopRunning()
            }
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.commitConfiguration()
        }
        state.captureSession = nil
        state.activeInput = nil
        state.activeDeviceID = nil
    }

    private static func publishStarted(state: CameraEngineState) {
        guard let session = state.captureSession, session.isRunning,
              let id = state.activeDeviceID,
              let device = discoveredDevices().first(where: { $0.id == id }) else { return }
        publish(.started(session: session, device: device), state: state)
    }

    private static func discoveredDevices() -> [CameraDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .deskViewCamera, .external],
            mediaType: .video,
            position: .unspecified
        )

        var seen = Set<String>()
        return discovery.devices.compactMap { device in
            guard seen.insert(device.uniqueID).inserted else { return nil }
            let kind: CameraDevice.Kind
            switch device.deviceType {
            case .builtInWideAngleCamera: kind = .builtIn
            case .continuityCamera: kind = .continuity
            case .deskViewCamera: kind = .deskView
            default: kind = .external
            }
            return CameraDevice(id: device.uniqueID, name: device.localizedName, kind: kind)
        }
    }

    private static func publishAuthorization(state: CameraEngineState) {
        publish(.authorization(AVCaptureDevice.authorizationStatus(for: .video)), state: state)
    }

    private static func publish(_ event: CameraSessionEvent, state: CameraEngineState) {
        guard let handler = state.callbacks.withLock({ $0.handler }) else { return }
        DispatchQueue.main.async {
            guard !state.callbacks.withLock({ $0.isShutDown }) else { return }
            handler(event)
        }
    }

    // MARK: - System events

    @objc private func deviceWasDisconnected(_ notification: Notification) {
        let deviceID = (notification.object as? AVCaptureDevice)?.uniqueID
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }) else { return }
            if deviceID == state.activeDeviceID {
                // The attached camera vanished: tear the session down. The
                // user's selection and intent stay untouched; for `automatic`
                // the reconciliation below picks the next available camera.
                Self.teardownSession(state: state)
            }
            Self.reconcile(state: state)
        }
    }

    @objc private func deviceWasConnected(_: Notification) {
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }) else { return }
            Self.reconcile(state: state)
        }
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        // macOS exposes no interruption reason for AVCaptureSession; log what
        // is available for diagnosis.
        Self.log.info(
            "capture session interrupted (userInfo: \(notification.userInfo?.count ?? 0, privacy: .public))"
        )

        let sessionID = (notification.object as? AVCaptureSession).map(ObjectIdentifier.init)
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }),
                  sessionID == nil || sessionID == state.captureSession.map(ObjectIdentifier.init) else { return }
            // Interruption is not an intentional stop: shouldRun is unchanged
            // and the session is kept, so the interruption ending can recover.
            Self.publish(.interrupted, state: state)
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        let sessionID = (notification.object as? AVCaptureSession).map(ObjectIdentifier.init)
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }), state.shouldRun else { return }
            guard let session = state.captureSession,
                  sessionID == nil || sessionID == ObjectIdentifier(session) else {
                Self.reconcile(state: state)
                return
            }
            if !session.isRunning {
                session.startRunning()
            }
            if session.isRunning {
                Self.publishStarted(state: state)
            } else {
                Self.reconcile(state: state)
            }
        }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        Self.log.error(
            "capture session runtime error: domain=\(error?.domain ?? "unknown", privacy: .public) code=\(error?.code ?? -1, privacy: .public) \(error?.localizedDescription ?? "no description", privacy: .public)"
        )

        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }), state.shouldRun else { return }
            // A runtime error must never wake the camera from an intentional stop.
            guard let session = state.captureSession else { return }

            // Media-services resets surface as this error on macOS; existing
            // session objects are stale, so recover through reconciliation.
            // DeviceWasDisconnected / DeviceNotConnected are handled by the
            // device-disconnect path, so just retry the normal restart here.
            if error?.domain == AVFoundationErrorDomain,
               error?.code == -11819 /* AVErrorMediaServicesWereReset (iOS) */ {
                Self.reconcile(state: state)
            } else if !session.isRunning {
                session.startRunning()
                if session.isRunning {
                    Self.publishStarted(state: state)
                } else {
                    Self.reconcile(state: state)
                }
            }
        }
    }

    @objc private func systemWillSleep(_: Notification) {
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }),
                  state.captureSession != nil else { return }
            // Tear the session down rather than pausing it: nothing can render
            // while the machine sleeps, and a fresh session on wake avoids the
            // paused-session-never-resumes failure mode. shouldRun is kept, so
            // the wake path rebuilds and resumes automatically.
            Self.teardownSession(state: state)
            Self.publish(.interrupted, state: state)
        }
    }

    @objc private func systemDidWake(_: Notification) {
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }), state.shouldRun else { return }
            guard let session = state.captureSession else {
                Self.reconcile(state: state)
                return
            }
            if !session.isRunning {
                session.startRunning()
            }
            if session.isRunning {
                Self.publishStarted(state: state)
            } else {
                // The camera may have disappeared during sleep.
                Self.reconcile(state: state)
            }
        }
    }

    private enum CameraSessionError: LocalizedError {
        case cannotAddInput

        var errorDescription: String? {
            "Cannot add the selected camera to the capture session"
        }
    }
}
