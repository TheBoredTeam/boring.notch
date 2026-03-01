//
//  WebcamView.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 19/08/24.
//

import AVFoundation
import Defaults
import SwiftUI

struct CameraPreviewView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager: WebcamManager
    
    // Track if authorization request is in progress to avoid multiple requests
    @State private var isRequestingAuthorization: Bool = false
    // Track the current state of mirror effect and the mirror icon in camera preview
    @Default(.isMirrored) private var isMirrored
    @Default(.enableFlipWebcamToggle) private var enableFlipWebcamToggle
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let previewLayer = webcamManager.previewLayer {
                    ZStack(alignment: .bottomTrailing) {
                        CameraPreviewLayerView(previewLayer: previewLayer)
                            .scaleEffect(x: isMirrored ? -1 : 1, y: 1)
                            .clipShape(RoundedRectangle(cornerRadius: Defaults[.mirrorShape] == .rectangle ? MusicPlayerImageSizes.cornerRadiusInset.opened : 100))
                            .frame(width: geometry.size.width, height: geometry.size.width)
                            .opacity(webcamManager.isSessionRunning ? 1 : 0)

                        // The mirror toggle button should only be visible if the webcam session is running and the setting to enable it is turned on
                        if enableFlipWebcamToggle && webcamManager.isSessionRunning {
                            Button {
                                isMirrored.toggle()
                            } label: {
                                Image(systemName: isMirrored ? "arrow.left.and.right.circle.fill" : "arrow.left.and.right.circle")
                                                            .font(.system(size: 14, weight: .semibold))
                                                            .foregroundStyle(.white.opacity(0.9))
                                                            .padding(6)
                                                            .background(.black.opacity(0.35), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                    }
                }

                if !webcamManager.isSessionRunning {
                    ZStack {
                        RoundedRectangle(cornerRadius: Defaults[.mirrorShape] == .rectangle ? MusicPlayerImageSizes.cornerRadiusInset.opened : 100)
                            .fill(Color(red: 20/255, green: 20/255, blue: 20/255))
                            .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                            .frame(width: geometry.size.width, height: geometry.size.width)
                        VStack(spacing: 8) {
                            Image(systemName: webcamManager.authorizationStatus == .denied ? "exclamationmark.triangle" : "web.camera")
                                .foregroundStyle(.gray)
                                .font(.system(size: geometry.size.width/3.5))
                            Text(webcamManager.authorizationStatus == .denied ? "Access Denied" : "Mirror")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .onTapGesture {
                handleCameraTap()
            }
            .onDisappear {
                webcamManager.stopSession()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private func handleCameraTap() {
        if isRequestingAuthorization {
            return // Prevent multiple authorization requests
        }
        
        switch webcamManager.authorizationStatus {
        case .authorized:
            if webcamManager.isSessionRunning {
                webcamManager.stopSession()
            } else if webcamManager.cameraAvailable {
                webcamManager.startSession()
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Camera Access Required"
                alert.informativeText = "Please allow camera access in System Settings to use the mirror feature."
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(settingsURL)
                    }
                }
            }
        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            // Reset the request flag after a reasonable delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isRequestingAuthorization = false
            }
        @unknown default:
            break
        }
    }
}

struct CameraPreviewLayerView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer = previewLayer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = nsView.bounds
        CATransaction.commit()
    }
}

#Preview {
    CameraPreviewView(webcamManager: .shared)
}
