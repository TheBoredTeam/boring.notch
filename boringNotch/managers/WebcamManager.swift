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
    struct Operation: Equatable, Sendable {
        let id = UUID()
        let owner: UUID?
        let preferredCameraID: String?
    }

    private let lock = NSLock()
    private var operation: Operation?

    var current: Operation? {
        lock.withLock { operation }
    }

    func requestStart(owner: UUID?, preferredCameraID: String?) -> Operation {
        lock.withLock {
            let next = Operation(owner: owner, preferredCameraID: preferredCameraID)
            operation = next
            return next
        }
    }

    func replace(_ expected: Operation, preferredCameraID: String?) -> Operation? {
        lock.withLock {
            guard operation == expected else { return nil }
            let next = Operation(owner: expected.owner, preferredCameraID: preferredCameraID)
            operation = next
            return next
        }
    }

    @discardableResult
    func requestStop(ifCurrent expected: Operation? = nil) -> Bool {
        lock.withLock {
            if let expected, operation != expected { return false }
            operation = nil
            return true
        }
    }

    func isCurrent(_ expected: Operation) -> Bool {
        lock.withLock { operation == expected }
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
    private struct ConfiguredSession {
        let session: AVCaptureSession
        let preferredCameraID: String?
        let deviceID: String?
    }

    // Installed capture metadata stays with the session it describes, on sessionQueue.
    private var configuredSession: ConfiguredSession?
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
        if configuredSession?.session.isRunning == true {
            configuredSession?.session.stopRunning()
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
        guard let current = intent.current else { return }
        startSessionOperation(current, preferredCameraID: id, reuseExistingSession: false)
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
        if let current = intent.current, current.owner != owner { stopSession() }
        sessionOwner = owner
        requestSessionStart(completion: completion)
    }

    func ownsSession(_ owner: UUID) -> Bool {
        intent.current?.owner == owner
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
        if let owner, intent.current?.owner != owner { return }
        intent.requestStop()
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

        if intent.current != nil {
            if isSessionRunning {
                finishPendingStarts(with: .started)
            }
            return
        }

        let operation = intent.requestStart(owner: sessionOwner, preferredCameraID: selectedCameraID)
        isSessionDesired = true

        switch refreshAuthorizationStatus() {
        case .authorized:
            startSessionOperation(operation, preferredCameraID: operation.preferredCameraID, reuseExistingSession: false)
        case .notDetermined:
            if !isRequestingAuthorization {
                isRequestingAuthorization = true
                dependencies.requestAccess { [weak self] granted in
                    self?.completeAuthorizationRequest(granted: granted)
                }
            }
        case .denied, .restricted:
            cancelStart(operation: operation, result: .accessDenied)
        @unknown default:
            cancelStart(operation: operation, result: .accessDenied)
        }
    }

    private func completeAuthorizationRequest(granted: Bool) {
        publishOnMain { [weak self] in
            guard let self else { return }
            self.isRequestingAuthorization = false
            self.authorizationStatus = granted ? .authorized : .denied

            guard let operation = self.intent.current else { return }
            if granted {
                self.startSessionOperation(operation, preferredCameraID: operation.preferredCameraID, reuseExistingSession: false)
            } else {
                self.cancelStart(operation: operation, result: .accessDenied)
            }
        }
    }

    private func cancelStart(operation: CameraSessionIntent.Operation, result: SessionStartResult) {
        precondition(Thread.isMainThread)
        guard intent.requestStop(ifCurrent: operation) else { return }
        isSessionDesired = false
        sessionOwner = nil
        isSessionRunning = false
        previewLayer = nil
        finishPendingStarts(with: result)
    }

    private func startSessionOperation(
        _ current: CameraSessionIntent.Operation,
        preferredCameraID: String?,
        reuseExistingSession: Bool
    ) {
        guard let operation = intent.replace(current, preferredCameraID: preferredCameraID) else { return }
        sessionQueue.async { [weak self] in
            self?.startOnSessionQueue(operation, reuseExistingSession: reuseExistingSession)
        }
    }

    private func startOnSessionQueue(
        _ operation: CameraSessionIntent.Operation,
        reuseExistingSession: Bool
    ) {
        guard intent.isCurrent(operation), dependencies.authorizationStatus() == .authorized else { return }
        if reuseExistingSession,
           let configuredSession,
           configuredSession.preferredCameraID == operation.preferredCameraID {
            let session = configuredSession.session
            if !session.isRunning { session.startRunning() }
            guard intent.isCurrent(operation) else {
                cleanupExistingSession()
                return
            }
            if session.isRunning {
                publishRunningSession(session, devices: dependencies.discoverDevices(), operation: operation)
                return
            }
        }

        cleanupExistingSession()
        publishStoppedSession(operation: operation)
        do {
            let session = dependencies.makeSession()
            let devices = dependencies.discoverDevices()
            let activeDeviceID = try dependencies.configureSession(session, devices, operation.preferredCameraID)

            guard intent.isCurrent(operation), dependencies.authorizationStatus() == .authorized else { return }
            configuredSession = ConfiguredSession(
                session: session,
                preferredCameraID: operation.preferredCameraID,
                deviceID: activeDeviceID
            )
            session.startRunning()

            guard intent.isCurrent(operation), session.isRunning else {
                cleanupExistingSession()
                publishStartFailure(operation: operation)
                return
            }

            publishRunningSession(session, devices: devices, operation: operation)
        } catch {
            NSLog("Failed to setup capture session: \(error.localizedDescription)")
            // Session work is serial: a replacement cannot have installed its
            // session here yet. The delayed publication must also match this attempt.
            cleanupExistingSession()
            publishStartFailure(operation: operation)
        }
    }

    private func publishRunningSession(
        _ session: AVCaptureSession,
        devices: [AVCaptureDevice],
        operation: CameraSessionIntent.Operation
    ) {
        publishOnMain { [weak self] in
            guard let self, self.intent.isCurrent(operation) else { return }
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

    private func publishStartFailure(operation: CameraSessionIntent.Operation) {
        publishOnMain { [weak self] in
            guard let self, self.intent.requestStop(ifCurrent: operation) else { return }
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
        guard let existingSession = configuredSession?.session else { return }

        if existingSession.isRunning {
            existingSession.stopRunning()
        }

        existingSession.beginConfiguration()
        existingSession.inputs.forEach(existingSession.removeInput)
        existingSession.outputs.forEach(existingSession.removeOutput)
        existingSession.commitConfiguration()
        configuredSession = nil
    }

    private func resumeSession(_ current: CameraSessionIntent.Operation) {
        startSessionOperation(current, preferredCameraID: current.preferredCameraID, reuseExistingSession: true)
    }

    private func publishStoppedSession(operation: CameraSessionIntent.Operation) {
        publishOnMain { [weak self] in
            guard let self, self.intent.isCurrent(operation) else { return }
            self.isSessionRunning = false
            self.previewLayer = nil
        }
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
            guard let self, let operation = self.intent.current else { return }
            self.resumeSession(operation)
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
        checkCameraAvailability()
        guard let disconnectedDevice = notification.object as? AVCaptureDevice else { return }
        sessionQueue.async { [weak self] in
            guard let self,
                  self.configuredSession?.deviceID == disconnectedDevice.uniqueID,
                  let operation = self.intent.current,
                  self.intent.isCurrent(operation) else { return }
            self.cleanupExistingSession()
            self.publishStoppedSession(operation: operation)
        }
    }

    private func deviceWasConnected() {
        checkCameraAvailability()
        guard let operation = intent.current else { return }
        resumeSession(operation)
    }

    private func suspendCurrentSession() {
        sessionQueue.async { [weak self] in
            guard let self,
                  let operation = self.intent.current,
                  self.intent.isCurrent(operation),
                  let session = self.configuredSession?.session else { return }
            if session.isRunning {
                session.stopRunning()
            }
            self.publishStoppedSession(operation: operation)
        }
    }

    private func sessionRuntimeError(_ notification: Notification) {
        guard let failedSession = notification.object as? AVCaptureSession else { return }
        sessionQueue.async { [weak self] in
            guard let self,
                  failedSession === self.configuredSession?.session,
                  let operation = self.intent.current,
                  self.intent.isCurrent(operation) else { return }
            guard let replacement = self.intent.replace(operation, preferredCameraID: operation.preferredCameraID) else { return }
            self.startOnSessionQueue(replacement, reuseExistingSession: false)
        }
    }

    private func sessionWasInterrupted(_ notification: Notification) {
        guard let interruptedSession = notification.object as? AVCaptureSession else { return }
        sessionQueue.async { [weak self] in
            guard let self,
                  interruptedSession === self.configuredSession?.session,
                  let operation = self.intent.current else { return }
            self.publishStoppedSession(operation: operation)
        }
    }

    private func sessionInterruptionEnded(_ notification: Notification) {
        guard let resumedSession = notification.object as? AVCaptureSession else { return }
        sessionQueue.async { [weak self] in
            guard let self,
                  resumedSession === self.configuredSession?.session,
                  let operation = self.intent.current else { return }
            self.resumeSession(operation)
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
