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
    case interrupted
    case failed(String)
}

/// Main-actor presentation model for the app's one shared camera dependency.
@MainActor
@Observable
final class CameraModel {
    private(set) var state: CameraState
    private(set) var authorizationStatus: AVAuthorizationStatus
    private(set) var availableCameras: [CameraDevice] = []
    private(set) var selection: CameraSelection = .automatic
    private(set) var activeCameraID: String?
    private(set) var activeSession: AVCaptureSession?
    private(set) var isIntendedRunning = false

    @ObservationIgnored private let engine: CameraSessionEngine
    @ObservationIgnored private var startAfterAuthorization = false
    @ObservationIgnored private var lastPublishedDeviceList: [CameraDevice]?

    var cameraAvailable: Bool { !availableCameras.isEmpty }
    var isSessionRunning: Bool { state == .running }

    private func syncEngineIfNeeded() {
        guard isIntendedRunning, authorizationStatus == .authorized else { return }
        let satisfiable: Bool
        switch selection {
        case .automatic:
            satisfiable = !availableCameras.isEmpty
        case .device(let id):
            satisfiable = availableCameras.contains { $0.id == id }
        }
        // Track the list even when unsatisfiable so the satisfying list that
        // arrives later (device reconnected) re-triggers the engine.
        let changed = lastPublishedDeviceList != availableCameras
        lastPublishedDeviceList = availableCameras
        guard changed, satisfiable else { return }
        engine.start(selection: selection)
    }

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
        isIntendedRunning = true

        guard cameraAvailable else {
            state = .unavailable
            engine.start(selection: selection)
            return
        }

        state = .starting
        engine.start(selection: selection)
    }

    func stopSession() {
        guard state != .stopped else { return }
        startAfterAuthorization = false
        isIntendedRunning = false
        state = .stopped
        engine.stop()
    }

    func shutdown() {
        isIntendedRunning = false
        engine.eventHandler = nil
        engine.shutdown()
    }

    func refresh() {
        engine.refresh()
    }

    func selectCamera(_ selection: CameraSelection) {
        guard selection != self.selection else { return }
        self.selection = selection

        guard isIntendedRunning else { return }
        // Pinning the camera that is already live needs no action: the session
        // exists, shows this device, and the engine confirms on its next
        // reconcile. Any other change hands off through .starting.
        if case .device(let id) = selection, id == activeCameraID { return }
        state = .starting
        engine.start(selection: selection)
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
                isIntendedRunning = false
                state = .permissionDenied
                engine.stop()
            case .notDetermined:
                state = .permissionRequired
            @unknown default:
                isIntendedRunning = false
                state = .permissionDenied
                engine.stop()
            }

        case .devices(let cameras):
            availableCameras = cameras
            guard authorizationStatus == .authorized else { return }

            if let active = activeCameraID, !cameras.contains(where: { $0.id == active }) {
                // The camera the engine actually opened is gone. Drop the
                // stale session so the UI never renders a dead preview; the
                // engine follows up with .started (automatic fell back) or
                // .stopped (explicit device missing).
                activeSession = nil
                activeCameraID = nil
                if state == .running {
                    state = .starting
                }
            }
            if cameras.isEmpty {
                // No hardware: show unavailable while keeping the running
                // intent, so reconnecting a camera recovers automatically.
                if state == .running || state == .starting {
                    state = .unavailable
                }
            }

            syncEngineIfNeeded()

        case .started(let session, let device):
            // A started event proves the engine was told to run; adopt that
            // intent so directly published sessions (recovery, wake, tests)
            // surface a live preview.
            isIntendedRunning = true
            lastPublishedDeviceList = availableCameras
            activeSession = session
            activeCameraID = device.id
            state = .running

        case .interrupted:
            if state == .running || state == .starting {
                state = .interrupted
            }

        case .stopped:
            activeSession = nil
            activeCameraID = nil
            lastPublishedDeviceList = nil
            state = cameraAvailable ? .stopped : .unavailable

        case .failed(let message):
            activeSession = nil
            activeCameraID = nil
            state = isIntendedRunning ? .failed(message) : .stopped
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
