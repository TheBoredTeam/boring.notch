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
        stopSession()
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
    
    private func checkCameraAvailability() {
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
            
            let session = AVCaptureSession()
            self.captureSession = session
            session.sessionPreset = .high
            
            guard let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.external, .builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices.first,
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                  session.canAddInput(videoInput)
            else {
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                    self.cameraAvailable = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.cameraAvailable = true
            }
            
            session.beginConfiguration()
            session.addInput(videoInput)
            
            let videoOutput = AVCaptureVideoDataOutput()
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            session.commitConfiguration()
            
            DispatchQueue.main.async {
                let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                previewLayer.videoGravity = .resizeAspectFill
                self.previewLayer = previewLayer
            }
            
            NSLog("Capture session setup completed")
        }
    }

    @objc private func deviceWasDisconnected(notification: Notification) {
        NSLog("Camera device was disconnected")
        stopSession() // Stop the session if the camera is disconnected
        DispatchQueue.main.async {
            self.previewLayer = nil // Clear the preview layer
            self.isSessionRunning = false // Update the session state
            self.checkCameraAvailability() // Re-check camera availability
        }
    }

    @objc private func deviceWasConnected(notification: Notification) {
        NSLog("Camera device was connected")
        checkCameraAvailability() // Check availability again when a device is connected
    }

    private func updateSessionState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isSessionRunning = self.captureSession?.isRunning ?? false
        }
    }
    
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession, !session.isRunning else { return }
            session.startRunning()
            self.updateSessionState()
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession, session.isRunning else { return }
            
            session.stopRunning()
            self.updateSessionState()
        }
    }
}
