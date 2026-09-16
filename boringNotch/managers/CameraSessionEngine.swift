//
//  CameraSessionEngine.swift
//  boringNotch
//
//  Created by Alexander on 2026-09-16.
//

import AVFoundation
import AppKit
import Foundation
import os.lock

struct CameraDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let isExternal: Bool
}

enum CameraSessionEvent: @unchecked Sendable {
    case authorization(AVAuthorizationStatus)
    case devices([CameraDevice])
    case started(previewLayer: AVCaptureVideoPreviewLayer, device: CameraDevice)
    case stopped
    case failed(String)
}

protocol CameraSessionEngine: AnyObject {
    var eventHandler: (@MainActor @Sendable (CameraSessionEvent) -> Void)? { get set }

    func refresh()
    func requestAccess()
    func start(cameraID: String?)
    func stop()
    func shutdown()
}

/// Owns AVFoundation objects and serializes all session work away from the UI.
private final class CameraEngineState: @unchecked Sendable {
    var captureSession: AVCaptureSession?
    var activeCameraID: String?
    var shouldRun = false
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

    func refresh() {
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }) else { return }
            Self.publishAuthorization(state: state)
            Self.publishDevices(state: state)
        }
    }

    func requestAccess() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let state = state
        Self.publish(.authorization(status), state: state)

        guard status == .notDetermined else {
            if status == .authorized {
                refresh()
            }
            return
        }

        let queue = sessionQueue
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Self.publish(.authorization(granted ? .authorized : .denied), state: state)
            if granted {
                Self.refresh(state: state, queue: queue)
            }
        }
    }

    func start(cameraID: String?) {
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }) else { return }
            state.shouldRun = true
            Self.startSession(cameraID: cameraID, state: state)
        }
    }

    func stop() {
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }) else { return }
            state.shouldRun = false
            Self.cleanupSession(state: state)
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
            Self.cleanupSession(state: state)
        }
    }

    private static func refresh(state: CameraEngineState, queue: DispatchQueue) {
        queue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }) else { return }
            publishAuthorization(state: state)
            publishDevices(state: state)
        }
    }

    private static func publishAuthorization(state: CameraEngineState) {
        publish(.authorization(AVCaptureDevice.authorizationStatus(for: .video)), state: state)
    }

    private static func publishDevices(state: CameraEngineState) {
        let devices = discoveredDevices()
        publish(.devices(devices), state: state)

        // A running preview should recover after a camera is unplugged and
        // replugged, or after another camera becomes available.
        if state.shouldRun, !devices.isEmpty, state.captureSession == nil {
            startSession(cameraID: state.activeCameraID, state: state)
        }
    }

    private static func discoveredDevices() -> [CameraDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )

        return discovery.devices
            .sorted { lhs, rhs in
                if lhs.deviceType == rhs.deviceType {
                    return lhs.localizedName < rhs.localizedName
                }
                return lhs.deviceType == .external
            }
            .map {
                CameraDevice(
                    id: $0.uniqueID,
                    name: $0.localizedName,
                    isExternal: $0.deviceType == .external
                )
            }
    }

    private static func startSession(cameraID: String?, state: CameraEngineState) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            publishAuthorization(state: state)
            return
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        let devices = discovery.devices
        guard !devices.isEmpty else {
            publish(.devices([]), state: state)
            return
        }

        let requestedID = cameraID ?? state.activeCameraID
        let videoDevice = devices.first { $0.uniqueID == requestedID }
            ?? devices.sorted { lhs, rhs in
                if lhs.deviceType == rhs.deviceType {
                    return lhs.localizedName < rhs.localizedName
                }
                return lhs.deviceType == .external
            }.first!

        cleanupSession(state: state)

        do {
            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .high

            let input = try AVCaptureDeviceInput(device: videoDevice)
            guard session.canAddInput(input) else {
                throw CameraSessionError.cannotAddInput
            }
            session.addInput(input)
            session.commitConfiguration()

            session.startRunning()
            state.captureSession = session
            state.activeCameraID = videoDevice.uniqueID

            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            let camera = CameraDevice(
                id: videoDevice.uniqueID,
                name: videoDevice.localizedName,
                isExternal: videoDevice.deviceType == .external
            )
            publish(.started(previewLayer: previewLayer, device: camera), state: state)
        } catch {
            cleanupSession(state: state)
            publish(.failed(error.localizedDescription), state: state)
        }
    }

    private static func cleanupSession(state: CameraEngineState) {
        guard let session = state.captureSession else { return }
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
        state.captureSession = nil
    }

    private static func publish(_ event: CameraSessionEvent, state: CameraEngineState) {
        guard let handler = state.callbacks.withLock({ $0.handler }) else { return }
        DispatchQueue.main.async {
            guard !state.callbacks.withLock({ $0.isShutDown }) else { return }
            handler(event)
        }
    }

    @objc private func deviceWasDisconnected(_ notification: Notification) {
        let deviceID = (notification.object as? AVCaptureDevice)?.uniqueID
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }) else { return }
            if deviceID == state.activeCameraID {
                Self.cleanupSession(state: state)
            }
            Self.publishDevices(state: state)
        }
    }

    @objc private func deviceWasConnected(_: Notification) {
        refresh()
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let hasError = notification.userInfo?[AVCaptureSessionErrorKey] != nil
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }), state.shouldRun else { return }
            Self.cleanupSession(state: state)
            Self.startSession(cameraID: state.activeCameraID, state: state)
            if !hasError {
                NSLog("Camera session reported an unknown runtime error and was restarted")
            }
        }
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        let sessionID = (notification.object as? AVCaptureSession).map(ObjectIdentifier.init)
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }),
                  sessionID == state.captureSession.map(ObjectIdentifier.init) else { return }
            Self.publish(.stopped, state: state)
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        let sessionID = (notification.object as? AVCaptureSession).map(ObjectIdentifier.init)
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }),
                  state.shouldRun,
                  sessionID == state.captureSession.map(ObjectIdentifier.init),
                  let session = state.captureSession else { return }
            if !session.isRunning {
                session.startRunning()
            }
            if session.isRunning {
                let camera = Self.discoveredDevices().first(where: { $0.id == state.activeCameraID })
                if let camera {
                    let layer = AVCaptureVideoPreviewLayer(session: session)
                    layer.videoGravity = .resizeAspectFill
                    Self.publish(.started(previewLayer: layer, device: camera), state: state)
                }
            }
        }
    }

    @objc private func systemWillSleep(_: Notification) {
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }), let session = state.captureSession else { return }
            if session.isRunning {
                session.stopRunning()
                Self.publish(.stopped, state: state)
            }
        }
    }

    @objc private func systemDidWake(_: Notification) {
        let state = state
        sessionQueue.async {
            guard !state.callbacks.withLock({ $0.isShutDown }), state.shouldRun else { return }
            if let session = state.captureSession, !session.isRunning {
                session.startRunning()
                if session.isRunning {
                    Self.publishDevices(state: state)
                }
            } else if state.captureSession == nil {
                Self.startSession(cameraID: state.activeCameraID, state: state)
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
