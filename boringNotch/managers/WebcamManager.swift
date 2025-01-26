//
//  WebcamManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 19/08/24.
//
import AVFoundation
import SwiftUI

class WebcamManager: NSObject, ObservableObject {
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

    private let sessionQueue = DispatchQueue(label: "BoringNotch.WebcamManager.SessionQueue", qos: .userInitiated)
    
    private var isCleaningUp: Bool = false
    
    override init() {
        super.init()
        checkAndRequestVideoAuthorization()
        NotificationCenter.default.addObserver(self, selector: #selector(deviceWasDisconnected), name: .AVCaptureDeviceWasDisconnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceWasConnected), name: .AVCaptureDeviceWasConnected, object: nil)
        checkCameraAvailability()
    }
    
    func cleanup() {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        
        // Remove observers first
        NotificationCenter.default.removeObserver(self)
        
        // Stop session and clear resources
        if let session = captureSession {
            // Stop running first if needed
            if session.isRunning {
                session.stopRunning()
            }
            captureSession = nil
        }
        
        // Clear preview layer on main thread
        DispatchQueue.main.async { [weak self] in
            self?.previewLayer = nil
            self?.isCleaningUp = false
        }
    }
    
    deinit {
        // Simple cleanup in deinit
        if let session = captureSession {
            session.stopRunning()
        }
        captureSession = nil
        previewLayer = nil
    }

    // Check current authorization status and handle it accordingly
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
    
    // Request access to the camera
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
    
    func checkCameraAvailability() {
        let availableDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external, .builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices
        if !availableDevices.isEmpty && captureSession == nil {
            setupCaptureSession()
        }
        DispatchQueue.main.async {
            self.cameraAvailable = !availableDevices.isEmpty
        }
    }
    
    private func setupCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Cleanup any existing session first
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
            
            let session = AVCaptureSession()
            
            do {
                // Get available devices and prefer external camera if available
                let discoverySession = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.external, .builtInWideAngleCamera],
                    mediaType: .video,
                    position: .unspecified
                )
                
                guard let videoDevice = discoverySession.devices.first else {
                    NSLog("No video devices available")
                    DispatchQueue.main.async {
                        self.isSessionRunning = false
                        self.cameraAvailable = false
                    }
                    return
                }
                
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
                }
                
                NSLog("Capture session setup completed successfully")
            } catch {
                NSLog("Failed to setup capture session: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                    self.cameraAvailable = false
                    self.previewLayer = nil
                }
            }
        }
    }

    @objc private func deviceWasDisconnected(notification: Notification) {
        NSLog("Camera device was disconnected")
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.stopSession()
            DispatchQueue.main.async {
                self.cameraAvailable = false
            }
        }
    }

    @objc private func deviceWasConnected(notification: Notification) {
        NSLog("Camera device was connected")
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.setupCaptureSession()
        }
    }

    private func updateSessionState() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let isRunning = self.captureSession?.isRunning ?? false
            DispatchQueue.main.async {
                self.isSessionRunning = isRunning
            }
        }
    }
    
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // If no session exists or preview layer is nil, create new session
            if self.captureSession == nil || self.previewLayer == nil {
                self.setupCaptureSession()
                return
            }
            
            guard let session = self.captureSession,
                  !session.isRunning else { return }
            
            session.startRunning()
            
            // Update state on main thread
            DispatchQueue.main.async {
                self.isSessionRunning = true
            }
            
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
            
            // Stop the session if it exists and is running
            if let session = self.captureSession {
                // First stop the session if running
                if session.isRunning {
                    session.stopRunning()
                }
                
                // Then begin configuration for cleanup
                session.beginConfiguration()
                
                // Remove all inputs and outputs
                for input in session.inputs {
                    session.removeInput(input)
                }
                for output in session.outputs {
                    session.removeOutput(output)
                }
                
                session.commitConfiguration()
                
                // Clear the session and preview layer
                self.captureSession = nil
                DispatchQueue.main.async {
                    self.previewLayer = nil
                }
            }
            
            NSLog("Capture session stopped and cleaned up")
        }
    }
}
