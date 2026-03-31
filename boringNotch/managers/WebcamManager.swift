//
//  WebcamManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 19/08/24.
//
import AVFoundation
import Defaults
import SwiftUI

class WebcamManager: NSObject, ObservableObject {
    static let shared = WebcamManager()
    
    @Published var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            objectWillChange.send()
        }
    }
    
    private var captureSession: AVCaptureSession?
    @Published var isSessionRunning: Bool = false {
        didSet {
            objectWillChange.send()
        }
    }
    
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined {
        didSet {
            objectWillChange.send()
        }
    }
    
    @Published var cameraAvailable: Bool = false {
        didSet {
            objectWillChange.send()
        }
    }

    @Published var availableCameras: [AVCaptureDevice] = [] {
        didSet {
            objectWillChange.send()
        }
    }

    @Published var selectedCameraID: String? {
        didSet {
            objectWillChange.send()
        }
    }

    private let sessionQueue = DispatchQueue(label: "BoringNotch.WebcamManager.SessionQueue", qos: .userInitiated)
    
    // MARK: - Constants
    
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
    
    // MARK: - Properties
    
    private override init() {
        self.selectedCameraID = Defaults[.mirrorCameraID]
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(deviceWasDisconnected), name: .AVCaptureDeviceWasDisconnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceWasConnected), name: .AVCaptureDeviceWasConnected, object: nil)
        checkCameraAvailability()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        if let session = captureSession {
            if session.isRunning {
                session.stopRunning()
            }
        }
        captureSession = nil
            
        previewLayer = nil
    }

    // MARK: - Camera Management

    private func discoverVideoDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    private func preferredDevice(from devices: [AVCaptureDevice], preferredID: String?) -> AVCaptureDevice? {
        guard !devices.isEmpty else { return nil }

        if let preferredID, let selectedDevice = devices.first(where: { $0.uniqueID == preferredID }) {
            return selectedDevice
        }

        // In automatic mode, prefer built-in camera over external devices (e.g. OBS virtual camera)
        return devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? devices.first
    }

    func setSelectedCamera(id: String?) {
        Defaults[.mirrorCameraID] = id
        selectedCameraID = id

        // Snapshot the ID before dispatching to avoid a cross-thread read of selectedCameraID.
        let snapshotID = id
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let session = self.captureSession, session.isRunning else { return }
            self.cleanupExistingSession()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
            self.setupCaptureSession(preferredID: snapshotID) { success in
                if success {
                    self.startRunningCaptureSession()
                }
            }
        }
    }

    /// Checks current authorization status and requests access if needed
    func checkAndRequestVideoAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
        
        switch status {
        case .authorized:
            checkCameraAvailability() // Check availability if authorized
        case .notDetermined:
            requestVideoAccess()
        case .denied, .restricted:
            NSLog("Camera access denied or restricted")
        @unknown default:
            NSLog("Unknown authorization status")
        }
    }
    
    /// Requests access to the camera
    private func requestVideoAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.authorizationStatus = granted ? .authorized : .denied
                if granted {
                    self?.checkCameraAvailability() // Check availability if access granted
                }
            }
        }
    }
    
    /// Checks if any camera devices are available and sets up capture session if needed
    func checkCameraAvailability() {
        let availableDevices = discoverVideoDevices()

        let hasAvailableDevices = !availableDevices.isEmpty

        DispatchQueue.main.async {
            self.availableCameras = availableDevices
            self.cameraAvailable = hasAvailableDevices
        }
    }
    
    /// Sets up the capture session with a completion handler.
    /// - Parameter preferredID: The camera ID to use. Pass explicitly to avoid cross-thread reads of `selectedCameraID`.
    ///   When `nil` is ambiguous (meaning "automatic"), callers on sessionQueue should snapshot `selectedCameraID` beforehand.
    private func setupCaptureSession(preferredID: String? = nil, completion: @escaping (Bool) -> Void) {
        let currentCameraID = preferredID ?? self.selectedCameraID
        sessionQueue.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }

            // Clean up any existing session before creating a new one
            self.cleanupExistingSession()

            let session = AVCaptureSession()

            do {
                let availableDevices = self.discoverVideoDevices()
                DispatchQueue.main.async {
                    self.availableCameras = availableDevices
                }

                guard let videoDevice = self.preferredDevice(from: availableDevices, preferredID: currentCameraID) else {
                    NSLog("No video devices available")
                    DispatchQueue.main.async {
                        self.isSessionRunning = false
                        self.cameraAvailable = false
                    }
                    completion(false)
                    return
                }
                
                NSLog("Using camera: \(videoDevice.localizedName)")
                
                // Lock device for configuration
                try videoDevice.lockForConfiguration()
                defer { videoDevice.unlockForConfiguration() }
                
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                guard session.canAddInput(videoInput) else {
                    throw NSError(domain: "BoringNotch.WebcamManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
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
                
                self.captureSession = session
                
                // Create and set up preview layer on main thread
                DispatchQueue.main.async {
                    self.cameraAvailable = true
                    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                    previewLayer.videoGravity = .resizeAspectFill
                    self.previewLayer = previewLayer
                    
                    // Setup is complete, let the caller know
                    completion(true)
                }
                
                NSLog("Capture session setup completed successfully")
            } catch {
                NSLog("Failed to setup capture session: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                    self.cameraAvailable = false
                    self.previewLayer = nil
                }
                completion(false)
            }
        }
    }
    
    /// Cleans up an existing capture session, removing all inputs and outputs
    private func cleanupExistingSession() {
        if let existingSession = self.captureSession {
            // First stop the session if running
            if existingSession.isRunning {
                existingSession.stopRunning()
            }
            
            // Then perform configuration cleanup
            existingSession.beginConfiguration()
            
            // Remove all inputs and outputs
            for input in existingSession.inputs {
                existingSession.removeInput(input)
            }
            for output in existingSession.outputs {
                existingSession.removeOutput(output)
            }
            
            existingSession.commitConfiguration()
            self.captureSession = nil
            
            // Clear preview layer on main thread
            DispatchQueue.main.async {
                self.previewLayer = nil
            }
        }
    }

    @objc private func deviceWasDisconnected(notification: Notification) {
        guard let disconnectedDevice = notification.object as? AVCaptureDevice else { return }
        NSLog("Camera device was disconnected: \(disconnectedDevice.localizedName)")

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            // Only tear down the session if the disconnected camera was the one in use
            let activeDeviceID = (self.captureSession?.inputs.first as? AVCaptureDeviceInput)?.device.uniqueID
            if activeDeviceID == disconnectedDevice.uniqueID {
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                }
                self.cleanupExistingSession()
            }

            self.checkCameraAvailability()
        }
    }

    @objc private func deviceWasConnected(notification: Notification) {
        NSLog("Camera device was connected")
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.checkCameraAvailability()
        }
    }

    private func updateSessionState() {
        let isRunning = self.captureSession?.isRunning ?? false
        DispatchQueue.main.async {
            self.isSessionRunning = isRunning
        }
    }
    
    func startSession() {
        // Snapshot the camera preference before dispatching to sessionQueue to avoid a data race.
        let snapshotID = self.selectedCameraID
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // If no session exists, create new session
            if self.captureSession == nil {
                self.setupCaptureSession(preferredID: snapshotID) { success in
                    if success {
                        // Only start the session if setup was successful
                        self.startRunningCaptureSession()
                    }
                }
            } else {
                // Session already exists, just start it
                self.startRunningCaptureSession()
            }
        }
    }
    
    private func startRunningCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession, !session.isRunning else {
                return
            }
            
            session.startRunning()
            
            // Update state on main thread
            self.updateSessionState()
            
            NSLog("Capture session started successfully")
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Update state to indicate we're stopping
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
            
            self.cleanupExistingSession()
            
            NSLog("Capture session stopped and cleaned up")
        }
    }
}
