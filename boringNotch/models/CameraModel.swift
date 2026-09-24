//
//  CameraModel.swift
//  boringNotch
//
//  Created by Alexander on 2026-09-16.
//

import AVFoundation
import Observation

enum CameraState: Equatable {
    case permissionRequired
    case requestingPermission
    case permissionDenied
    case unavailable
    case stopped
    case starting
    case running
    case failed(String)
}

/// Main-actor presentation model for the app's one shared camera dependency.
@MainActor
@Observable
final class CameraModel {
    private(set) var state: CameraState
    private(set) var authorizationStatus: AVAuthorizationStatus
    private(set) var availableCameras: [CameraDevice] = []
    private(set) var selectedCameraID: String?
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    @ObservationIgnored private let engine: CameraSessionEngine
    @ObservationIgnored private var startAfterAuthorization = false

    var cameraAvailable: Bool { !availableCameras.isEmpty }
    var isSessionRunning: Bool { state == .running }

    init(
        engine: CameraSessionEngine = AVCaptureSessionEngine(),
        authorizationStatus: AVAuthorizationStatus? = nil
    ) {
        self.engine = engine
        let status = authorizationStatus ?? AVCaptureDevice.authorizationStatus(for: .video)
        self.authorizationStatus = status
        state = Self.state(for: status)

        engine.eventHandler = { [weak self] event in
            self?.handle(event)
        }
        engine.refresh()
    }

    deinit {
        engine.shutdown()
    }

    func requestAccess() {
        guard state != .requestingPermission else { return }
        startAfterAuthorization = true
        state = .requestingPermission
        engine.requestAccess()
    }

    func startSession() {
        guard authorizationStatus == .authorized else {
            requestAccess()
            return
        }
        startAfterAuthorization = false
        guard cameraAvailable else {
            state = .unavailable
            engine.refresh()
            return
        }

        state = .starting
        engine.start(cameraID: selectedCameraID)
    }

    func stopSession() {
        guard state != .stopped else { return }
        startAfterAuthorization = false
        state = .stopped
        engine.stop()
    }

    func shutdown() {
        engine.shutdown()
    }

    func refresh() {
        engine.refresh()
    }

    func selectCamera(_ cameraID: String?) {
        if let cameraID, !availableCameras.contains(where: { $0.id == cameraID }) {
            return
        }
        selectedCameraID = cameraID
        if isSessionRunning || state == .starting {
            state = .starting
            engine.start(cameraID: cameraID)
        }
    }

    private func handle(_ event: CameraSessionEvent) {
        switch event {
        case .authorization(let status):
            let previousStatus = authorizationStatus
            authorizationStatus = status
            switch status {
            case .authorized:
                let shouldStart = startAfterAuthorization
                startAfterAuthorization = false
                if state == .permissionRequired || state == .requestingPermission
                    || state == .permissionDenied {
                    state = .stopped
                }
                // Only rediscover devices when access is newly granted. The engine
                // republishes the authorization status on every refresh, so refreshing
                // unconditionally here would loop forever once access is granted.
                if previousStatus != .authorized {
                    engine.refresh()
                }
                if shouldStart {
                    startSession()
                }
            case .denied, .restricted:
                state = .permissionDenied
            case .notDetermined:
                state = .permissionRequired
            @unknown default:
                state = .permissionDenied
            }

        case .devices(let cameras):
            availableCameras = cameras
            if cameras.isEmpty {
                selectedCameraID = nil
                previewLayer = nil
                if authorizationStatus == .authorized {
                    state = .unavailable
                }
                return
            }
            if let selectedCameraID, cameras.contains(where: { $0.id == selectedCameraID }) {
                return
            }
            selectedCameraID = cameras.first?.id

        case .started(let layer, let camera):
            selectedCameraID = camera.id
            previewLayer = layer
            state = .running

        case .stopped:
            previewLayer = nil
            state = cameraAvailable ? .stopped : .unavailable

        case .failed(let message):
            previewLayer = nil
            state = .failed(message)
        }
    }

    private static func state(for status: AVAuthorizationStatus) -> CameraState {
        switch status {
        case .authorized:
            return .stopped
        case .denied, .restricted:
            return .permissionDenied
        case .notDetermined:
            return .permissionRequired
        @unknown default:
            return .permissionDenied
        }
    }
}
