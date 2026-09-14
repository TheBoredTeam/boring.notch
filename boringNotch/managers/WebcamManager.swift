//
//  WebcamManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 19/08/24.
//
@preconcurrency import AVFoundation
@preconcurrency import Dispatch
@preconcurrency import Foundation
import Defaults
import SwiftUI

private final class CameraSessionIntent: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt = 0
    private var desired = false

    func requestStart() -> UInt {
        lock.withLock {
            generation &+= 1
            desired = true
            return generation
        }
    }

    func requestStop() {
        lock.withLock {
            generation &+= 1
            desired = false
        }
    }

    func isCurrent(_ expectedGeneration: UInt) -> Bool {
        lock.withLock {
            desired && generation == expectedGeneration
        }
    }

    var isDesired: Bool {
        lock.withLock { desired }
    }
}

final class WebcamManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = WebcamManager()

    enum SessionStartResult: Equatable {
        case started
        case accessDenied
        case unavailable
        case cancelled
    }

    struct Dependencies {
        var authorizationStatus: () -> AVAuthorizationStatus
        var requestAccess: (@escaping @Sendable (Bool) -> Void) -> Void
        var discoverDevices: () -> [AVCaptureDevice]
        var configureSession: (AVCaptureSession, [AVCaptureDevice], String?) throws -> String?
        var makeSession: () -> AVCaptureSession
        var makePreviewLayer: (AVCaptureSession) -> AVCaptureVideoPreviewLayer
        var notificationCenter: NotificationCenter
        var workspaceNotificationCenter: NotificationCenter
        var persistSelectedCamera: (String?) -> Void = { Defaults[.mirrorCameraID] = $0 }

        static var live: Dependencies {
            Dependencies(
                authorizationStatus: { AVCaptureDevice.authorizationStatus(for: .video) },
                requestAccess: { completion in
                    AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
                },
                discoverDevices: WebcamManager.discoverVideoDevices,
                configureSession: WebcamManager.configure,
                makeSession: AVCaptureSession.init,
                makePreviewLayer: { AVCaptureVideoPreviewLayer(session: $0) },
                notificationCenter: .default,
                workspaceNotificationCenter: NSWorkspace.shared.notificationCenter
            )
        }
    }

    @Published private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    @Published private(set) var isSessionRunning = false
    @Published private(set) var isSessionDesired = false
    @Published private(set) var sessionOwner: UUID?
    @Published private(set) var isRequestingAuthorization = false
    @Published private(set) var authorizationStatus: AVAuthorizationStatus
    @Published private(set) var cameraAvailable = false
    @Published private(set) var availableCameras: [AVCaptureDevice] = []
    @Published private(set) var selectedCameraID: String?

    private let dependencies: Dependencies
    private let sessionQueue: DispatchQueue
    private let intent = CameraSessionIntent()
    private let generationLock = NSLock()
    private var activeGeneration: UInt?
    private var activePreferredCameraID: String?
    private var captureSession: AVCaptureSession?
    private var activeDeviceID: String?
    private var pendingStartCompletions: [(SessionStartResult) -> Void] = []
    private var notificationTokens: [(NotificationCenter, NSObjectProtocol)] = []

    enum WebcamError: Error, LocalizedError {
        case deviceUnavailable
        case accessDenied
        case configurationFailed(String)

        var errorDescription: String? {
            switch self {
            case .deviceUnavailable:
                return "No camera devices available"
            case .accessDenied:
                return "Camera access denied"
            case .configurationFailed(let message):
                return "Camera configuration failed: \(message)"
            }
        }
    }

    private override convenience init() {
        self.init(dependencies: .live, selectedCameraID: Defaults[.mirrorCameraID])
    }

    init(
        dependencies: Dependencies,
        selectedCameraID: String? = nil,
        sessionQueue: DispatchQueue = DispatchQueue(
            label: "BoringNotch.WebcamManager.SessionQueue",
            qos: .userInitiated
        )
    ) {
        self.dependencies = dependencies
        self.selectedCameraID = selectedCameraID
        self.authorizationStatus = dependencies.authorizationStatus()
        self.sessionQueue = sessionQueue
        super.init()
        observeLifecycleEvents()
        checkCameraAvailability()
    }

    deinit {
        notificationTokens.forEach { center, token in
            center.removeObserver(token)
        }
        intent.requestStop()
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
    }

    private static func discoverVideoDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    private static func preferredDevice(
        from devices: [AVCaptureDevice],
        preferredID: String?
    ) -> AVCaptureDevice? {
        guard !devices.isEmpty else { return nil }

        if let preferredID,
           let selectedDevice = devices.first(where: { $0.uniqueID == preferredID }) {
            return selectedDevice
        }

        // In automatic mode, prefer a built-in camera over external devices such as OBS.
        return devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? devices.first
    }

    private static func configure(
        session: AVCaptureSession,
        devices: [AVCaptureDevice],
        preferredID: String?
    ) throws -> String? {
        guard let videoDevice = preferredDevice(from: devices, preferredID: preferredID) else {
            throw WebcamError.deviceUnavailable
        }

        NSLog("Using camera: \(videoDevice.localizedName)")
        try videoDevice.lockForConfiguration()
        defer { videoDevice.unlockForConfiguration() }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        guard session.canAddInput(videoInput) else {
            throw WebcamError.configurationFailed("Cannot add video input")
        }

        session.beginConfiguration()
        session.sessionPreset = .high
        session.addInput(videoInput)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()
        return videoDevice.uniqueID
    }

    func setSelectedCamera(id: String?) {
        precondition(Thread.isMainThread)
        dependencies.persistSelectedCamera(id)
        selectedCameraID = id
        setCurrentPreferredCameraID(id)

        guard let generation = currentGeneration(), intent.isCurrent(generation) else { return }
        restartSession(generation: generation, preferredID: id)
    }

    @discardableResult
    func refreshAuthorizationStatus() -> AVAuthorizationStatus {
        precondition(Thread.isMainThread)
        let status = dependencies.authorizationStatus()
        authorizationStatus = status
        return status
    }

    func checkCameraAvailability() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let devices = self.dependencies.discoverDevices()
            self.publishOnMain {
                self.availableCameras = devices
                self.cameraAvailable = !devices.isEmpty
            }
        }
    }

    func startSession(owner: UUID? = nil, completion: ((SessionStartResult) -> Void)? = nil) {
        precondition(Thread.isMainThread)
        if isSessionDesired && sessionOwner != owner { stopSession() }
        sessionOwner = owner
        requestSessionStart(completion: completion)
    }

    func ownsSession(_ owner: UUID) -> Bool {
        isSessionDesired && sessionOwner == owner
    }

    nonisolated func releaseSession(owner: UUID) {
        if Thread.isMainThread {
            stopSession(owner: owner)
        } else {
            DispatchQueue.main.async { [self] in
                stopSession(owner: owner)
            }
        }
    }

    func stopSession(owner: UUID? = nil) {
        precondition(Thread.isMainThread)
        if let owner, sessionOwner != owner { return }
        intent.requestStop()
        setCurrentGeneration(nil)
        isSessionDesired = false
        sessionOwner = nil
        isSessionRunning = false
        previewLayer = nil
        finishPendingStarts(with: .cancelled)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.cleanupExistingSession()
            NSLog("Capture session stopped and cleaned up")
        }
    }

    private func requestSessionStart(completion: ((SessionStartResult) -> Void)?) {
        precondition(Thread.isMainThread)

        if let completion {
            pendingStartCompletions.append(completion)
        }

        if intent.isDesired {
            if isSessionRunning {
                finishPendingStarts(with: .started)
            }
            return
        }

        let generation = intent.requestStart()
        setCurrentGeneration(generation, preferredCameraID: selectedCameraID)
        isSessionDesired = true

        switch refreshAuthorizationStatus() {
        case .authorized:
            configureAndStart(generation: generation)
        case .notDetermined:
            if !isRequestingAuthorization {
                isRequestingAuthorization = true
                dependencies.requestAccess { [weak self] granted in
                    self?.completeAuthorizationRequest(granted: granted)
                }
            }
        case .denied, .restricted:
            cancelStart(generation: generation, result: .accessDenied)
        @unknown default:
            cancelStart(generation: generation, result: .accessDenied)
        }
    }

    private func completeAuthorizationRequest(granted: Bool) {
        publishOnMain { [weak self] in
            guard let self else { return }
            self.isRequestingAuthorization = false
            self.authorizationStatus = granted ? .authorized : .denied

            guard let generation = self.currentGeneration() else { return }
            guard self.intent.isCurrent(generation) else { return }
            if granted {
                self.configureAndStart(generation: generation)
            } else {
                self.cancelStart(generation: generation, result: .accessDenied)
            }
        }
    }

    private func cancelStart(generation: UInt, result: SessionStartResult) {
        precondition(Thread.isMainThread)
        guard intent.isCurrent(generation) else { return }
        intent.requestStop()
        setCurrentGeneration(nil)
        isSessionDesired = false
        sessionOwner = nil
        isSessionRunning = false
        previewLayer = nil
        finishPendingStarts(with: result)
    }

    private func configureAndStart(generation: UInt) {
        let preferredID = selectedCameraID
        sessionQueue.async { [weak self] in
            self?.configureAndStartOnSessionQueue(generation: generation, preferredID: preferredID)
        }
    }

    private func configureAndStartOnSessionQueue(generation: UInt, preferredID: String?) {
        guard intent.isCurrent(generation), dependencies.authorizationStatus() == .authorized else { return }
        cleanupExistingSession()

        do {
            let session = dependencies.makeSession()
            let devices = dependencies.discoverDevices()
            let activeDeviceID = try dependencies.configureSession(session, devices, preferredID)

            guard intent.isCurrent(generation), dependencies.authorizationStatus() == .authorized else { return }
            captureSession = session
            self.activeDeviceID = activeDeviceID
            session.startRunning()

            guard intent.isCurrent(generation), session.isRunning else {
                cleanupExistingSession()
                if intent.isCurrent(generation) {
                    publishStartFailure(generation: generation)
                }
                return
            }

            publishRunningSession(session, devices: devices, generation: generation)
        } catch {
            NSLog("Failed to setup capture session: \(error.localizedDescription)")
            cleanupExistingSession()
            publishStartFailure(generation: generation)
        }
    }

    private func publishRunningSession(
        _ session: AVCaptureSession,
        devices: [AVCaptureDevice],
        generation: UInt
    ) {
        publishOnMain { [weak self] in
            guard let self, self.intent.isCurrent(generation) else { return }
            self.availableCameras = devices
            self.cameraAvailable = true
            let previewLayer: AVCaptureVideoPreviewLayer
            if let currentLayer = self.previewLayer, currentLayer.session === session {
                previewLayer = currentLayer
            } else {
                previewLayer = self.dependencies.makePreviewLayer(session)
            }
            previewLayer.videoGravity = .resizeAspectFill
            self.previewLayer = previewLayer
            self.isSessionRunning = true
            self.finishPendingStarts(with: .started)
        }
    }

    private func publishStartFailure(generation: UInt) {
        publishOnMain { [weak self] in
            guard let self, self.intent.isCurrent(generation) else { return }
            self.intent.requestStop()
            self.setCurrentGeneration(nil)
            self.isSessionDesired = false
            self.sessionOwner = nil
            self.isSessionRunning = false
            self.previewLayer = nil
            self.cameraAvailable = false
            self.finishPendingStarts(with: .unavailable)
        }
    }

    private func finishPendingStarts(with result: SessionStartResult) {
        precondition(Thread.isMainThread)
        let completions = pendingStartCompletions
        pendingStartCompletions.removeAll()
        completions.forEach { $0(result) }
    }

    private func cleanupExistingSession() {
        guard let existingSession = captureSession else {
            activeDeviceID = nil
            return
        }

        if existingSession.isRunning {
            existingSession.stopRunning()
        }

        existingSession.beginConfiguration()
        existingSession.inputs.forEach(existingSession.removeInput)
        existingSession.outputs.forEach(existingSession.removeOutput)
        existingSession.commitConfiguration()
        captureSession = nil
        activeDeviceID = nil
    }

    private func restartSession(generation: UInt, preferredID: String?) {
        sessionQueue.async { [weak self] in
            guard let self, self.intent.isCurrent(generation),
                  self.dependencies.authorizationStatus() == .authorized else { return }
            self.cleanupExistingSession()
            self.publishStoppedSession(generation: generation)
            self.configureAndStartOnSessionQueue(
                generation: generation,
                preferredID: preferredID
            )
        }
    }

    private func resumeSession(generation: UInt) {
        sessionQueue.async { [weak self] in
            guard let self, self.intent.isCurrent(generation),
                  self.dependencies.authorizationStatus() == .authorized else { return }

            if let session = self.captureSession {
                if !session.isRunning {
                    session.startRunning()
                }

                if session.isRunning {
                    self.publishRunningSession(
                        session,
                        devices: self.dependencies.discoverDevices(),
                        generation: generation
                    )
                    return
                }
            }

            self.cleanupExistingSession()
            self.configureAndStartOnSessionQueue(
                generation: generation,
                preferredID: self.currentPreferredCameraID()
            )
        }
    }

    private func publishStoppedSession(generation: UInt) {
        publishOnMain { [weak self] in
            guard let self, self.intent.isCurrent(generation) else { return }
            self.isSessionRunning = false
            self.previewLayer = nil
        }
    }

    private func currentGeneration() -> UInt? {
        generationLock.withLock { activeGeneration }
    }

    private func setCurrentGeneration(
        _ generation: UInt?,
        preferredCameraID: String? = nil
    ) {
        generationLock.withLock {
            activeGeneration = generation
            activePreferredCameraID = generation == nil ? nil : preferredCameraID
        }
    }

    private func setCurrentPreferredCameraID(_ id: String?) {
        generationLock.withLock {
            activePreferredCameraID = id
        }
    }

    private func currentPreferredCameraID() -> String? {
        generationLock.withLock { activePreferredCameraID }
    }

    private func observeLifecycleEvents() {
        observe(AVCaptureDevice.wasDisconnectedNotification, center: dependencies.notificationCenter) {
            [weak self] notification in
            self?.deviceWasDisconnected(notification)
        }
        observe(AVCaptureDevice.wasConnectedNotification, center: dependencies.notificationCenter) {
            [weak self] _ in
            self?.deviceWasConnected()
        }
        observe(AVCaptureSession.runtimeErrorNotification, center: dependencies.notificationCenter) {
            [weak self] notification in
            self?.sessionRuntimeError(notification)
        }
        observe(AVCaptureSession.wasInterruptedNotification, center: dependencies.notificationCenter) {
            [weak self] notification in
            self?.sessionWasInterrupted(notification)
        }
        observe(AVCaptureSession.interruptionEndedNotification, center: dependencies.notificationCenter) {
            [weak self] notification in
            self?.sessionInterruptionEnded(notification)
        }
        observe(NSWorkspace.didWakeNotification, center: dependencies.workspaceNotificationCenter) {
            [weak self] _ in
            guard let self, let generation = self.currentGeneration() else { return }
            self.resumeSession(generation: generation)
        }
        observe(NSWorkspace.willSleepNotification, center: dependencies.workspaceNotificationCenter) {
            [weak self] _ in
            self?.suspendCurrentSession()
        }
    }

    private func observe(
        _ name: Notification.Name,
        center: NotificationCenter,
        handler: @escaping @Sendable (Notification) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: nil, using: handler)
        notificationTokens.append((center, token))
    }

    private func deviceWasDisconnected(_ notification: Notification) {
        guard let disconnectedDevice = notification.object as? AVCaptureDevice else { return }
        sessionQueue.async { [weak self] in
            guard let self,
                  self.activeDeviceID == disconnectedDevice.uniqueID,
                  let generation = self.currentGeneration(),
                  self.intent.isCurrent(generation) else { return }
            self.cleanupExistingSession()
            self.publishStoppedSession(generation: generation)
        }
    }

    private func deviceWasConnected() {
        checkCameraAvailability()
        guard let generation = currentGeneration(), intent.isCurrent(generation) else { return }
        resumeSession(generation: generation)
    }

    private func suspendCurrentSession() {
        sessionQueue.async { [weak self] in
            guard let self,
                  let generation = self.currentGeneration(),
                  self.intent.isCurrent(generation),
                  let session = self.captureSession else { return }
            if session.isRunning {
                session.stopRunning()
            }
            self.publishStoppedSession(generation: generation)
        }
    }

    private func sessionRuntimeError(_ notification: Notification) {
        guard let failedSession = notification.object as? AVCaptureSession else { return }
        sessionQueue.async { [weak self] in
            guard let self,
                  failedSession === self.captureSession,
                  let generation = self.currentGeneration(),
                  self.intent.isCurrent(generation) else { return }
            self.cleanupExistingSession()
            self.publishStoppedSession(generation: generation)
            self.configureAndStartOnSessionQueue(
                generation: generation,
                preferredID: self.currentPreferredCameraID()
            )
        }
    }

    private func sessionWasInterrupted(_ notification: Notification) {
        guard let interruptedSession = notification.object as? AVCaptureSession else { return }
        sessionQueue.async { [weak self] in
            guard let self,
                  interruptedSession === self.captureSession,
                  let generation = self.currentGeneration() else { return }
            self.publishStoppedSession(generation: generation)
        }
    }

    private func sessionInterruptionEnded(_ notification: Notification) {
        guard let resumedSession = notification.object as? AVCaptureSession else { return }
        sessionQueue.async { [weak self] in
            guard let self,
                  resumedSession === self.captureSession,
                  self.dependencies.authorizationStatus() == .authorized,
                  let generation = self.currentGeneration(),
                  self.intent.isCurrent(generation) else { return }
            if !resumedSession.isRunning {
                resumedSession.startRunning()
            }
            if resumedSession.isRunning {
                self.publishRunningSession(
                    resumedSession,
                    devices: self.dependencies.discoverDevices(),
                    generation: generation
                )
            } else {
                self.cleanupExistingSession()
                self.configureAndStartOnSessionQueue(
                    generation: generation,
                    preferredID: self.currentPreferredCameraID()
                )
            }
        }
    }

    private func publishOnMain(_ work: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ work: () -> T) -> T {
        lock()
        defer { unlock() }
        return work()
    }
}
