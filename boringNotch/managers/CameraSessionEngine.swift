//
//  CameraSessionEngine.swift
//  boringNotch
//
//  Created by Alexander on 2026-09-16.
//

import AVFoundation
import AppKit
import Foundation

struct CameraDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let isExternal: Bool
}

enum CameraSessionEvent {
    case authorization(AVAuthorizationStatus)
    case devices([CameraDevice])
    case started(previewLayer: AVCaptureVideoPreviewLayer, device: CameraDevice)
    case stopped
    case failed(String)
}

protocol CameraSessionEngine: AnyObject {
    var eventHandler: ((CameraSessionEvent) -> Void)? { get set }

    func refresh()
    func requestAccess()
    func start(cameraID: String?)
    func stop()
    func shutdown()
}

/// Owns AVFoundation objects and serializes all session work away from the UI.
final class AVCaptureSessionEngine: NSObject, CameraSessionEngine {
    var eventHandler: ((CameraSessionEvent) -> Void)?

    private let sessionQueue = DispatchQueue(
        label: "BoringNotch.CameraSessionEngine",
        qos: .userInitiated
    )
    private let notificationCenter: NotificationCenter
    private var captureSession: AVCaptureSession?
    private var activeCameraID: String?
    private var shouldRun = false
    private var isShutDown = false

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
        sessionQueue.async { [weak self] in
            guard let self, !self.isShutDown else { return }
            self.publishAuthorization()
            self.publishDevices()
        }
    }

    func requestAccess() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        publish(.authorization(status))

        guard status == .notDetermined else {
            if status == .authorized {
                refresh()
            }
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            self.publish(.authorization(granted ? .authorized : .denied))
            if granted {
                self.refresh()
            }
        }
    }

    func start(cameraID: String?) {
        sessionQueue.async { [weak self] in
            guard let self, !self.isShutDown else { return }
            self.shouldRun = true
            self.startSession(cameraID: cameraID)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isShutDown else { return }
            self.shouldRun = false
            self.cleanupSession()
            self.publish(.stopped)
        }
    }

    func shutdown() {
        sessionQueue.sync {
            guard !isShutDown else { return }
            isShutDown = true
            shouldRun = false
            cleanupSession()
        }
    }

    private func publishAuthorization() {
        publish(.authorization(AVCaptureDevice.authorizationStatus(for: .video)))
    }

    private func publishDevices() {
        let devices = discoveredDevices()
        publish(.devices(devices))

        // A running preview should recover after a camera is unplugged and
        // replugged, or after another camera becomes available.
        if shouldRun, !devices.isEmpty, captureSession == nil {
            startSession(cameraID: activeCameraID)
        }
    }

    private func discoveredDevices() -> [CameraDevice] {
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

    private func startSession(cameraID: String?) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            publishAuthorization()
            return
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        let devices = discovery.devices
        guard !devices.isEmpty else {
            publish(.devices([]))
            return
        }

        let requestedID = cameraID ?? activeCameraID
        let videoDevice = devices.first { $0.uniqueID == requestedID }
            ?? devices.sorted { lhs, rhs in
                if lhs.deviceType == rhs.deviceType {
                    return lhs.localizedName < rhs.localizedName
                }
                return lhs.deviceType == .external
            }.first!

        cleanupSession()

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
            captureSession = session
            activeCameraID = videoDevice.uniqueID

            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            let camera = CameraDevice(
                id: videoDevice.uniqueID,
                name: videoDevice.localizedName,
                isExternal: videoDevice.deviceType == .external
            )
            publish(.started(previewLayer: previewLayer, device: camera))
        } catch {
            cleanupSession()
            publish(.failed(error.localizedDescription))
        }
    }

    private func cleanupSession() {
        guard let session = captureSession else { return }
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
        captureSession = nil
    }

    private func publish(_ event: CameraSessionEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isShutDown else { return }
            self.eventHandler?(event)
        }
    }

    @objc private func deviceWasDisconnected(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            guard let self, !self.isShutDown else { return }
            if let device = notification.object as? AVCaptureDevice,
               device.uniqueID == self.activeCameraID {
                self.cleanupSession()
            }
            self.publishDevices()
        }
    }

    @objc private func deviceWasConnected(_: Notification) {
        refresh()
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            guard let self, !self.isShutDown, self.shouldRun else { return }
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            self.cleanupSession()
            self.startSession(cameraID: self.activeCameraID)
            if error == nil {
                NSLog("Camera session reported an unknown runtime error and was restarted")
            }
        }
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            guard let self,
                  !self.isShutDown,
                  let session = notification.object as? AVCaptureSession,
                  session === self.captureSession else { return }
            self.publish(.stopped)
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            guard let self,
                  !self.isShutDown,
                  self.shouldRun,
                  let session = notification.object as? AVCaptureSession,
                  session === self.captureSession else { return }
            if !session.isRunning {
                session.startRunning()
            }
            if session.isRunning {
                let camera = self.discoveredDevices().first(where: { $0.id == self.activeCameraID })
                if let camera {
                    let layer = AVCaptureVideoPreviewLayer(session: session)
                    layer.videoGravity = .resizeAspectFill
                    self.publish(.started(previewLayer: layer, device: camera))
                }
            }
        }
    }

    @objc private func systemWillSleep(_: Notification) {
        sessionQueue.async { [weak self] in
            guard let self, !self.isShutDown, let session = self.captureSession else { return }
            if session.isRunning {
                session.stopRunning()
                self.publish(.stopped)
            }
        }
    }

    @objc private func systemDidWake(_: Notification) {
        sessionQueue.async { [weak self] in
            guard let self, !self.isShutDown, self.shouldRun else { return }
            if let session = self.captureSession, !session.isRunning {
                session.startRunning()
                if session.isRunning {
                    self.publishDevices()
                }
            } else if self.captureSession == nil {
                self.startSession(cameraID: self.activeCameraID)
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
