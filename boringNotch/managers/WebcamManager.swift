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
    
    override init() {
        super.init()
        checkAndRequestVideoAuthorization()
        NotificationCenter.default.addObserver(self, selector: #selector(deviceWasDisconnected), name: .AVCaptureDeviceWasDisconnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceWasConnected), name: .AVCaptureDeviceWasConnected, object: nil)
        checkCameraAvailability()
    }
    
    deinit {
        // Ensure we stop the session before deallocating
        let semaphore = DispatchSemaphore(value: 0)
        sessionQueue.async { [weak self] in
            self?.stopSession()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1.0)
        NotificationCenter.default.removeObserver(self)
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
                existingSession.stopRunning()
                self.captureSession = nil
                
                // Clear preview layer on main thread
                DispatchQueue.main.async {
                    self.previewLayer = nil
                }
            }
            
            let session = AVCaptureSession()
            
            do {
                guard let videoDevice = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.external, .builtInWideAngleCamera],
                    mediaType: .video,
                    position: .unspecified
                ).devices.first else {
                    DispatchQueue.main.async {
                        self.isSessionRunning = false
                        self.cameraAvailable = false
                    }
                    return
                }
                
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
            
            // Stop the session if it exists and is running
            if let session = self.captureSession {
                if session.isRunning {
                    session.stopRunning()
                }
                
                // Clear the session and preview layer
                self.captureSession = nil
                DispatchQueue.main.async {
                    self.previewLayer = nil
                }
            }
            
            NSLog("Capture session stopped")
        }
    }
}
