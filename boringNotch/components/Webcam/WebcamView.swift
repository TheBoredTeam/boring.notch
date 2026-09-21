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
    @Default(.isMirrored) private var isMirrored
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let previewLayer = camera.previewLayer {
                    CameraPreviewLayerView(previewLayer: previewLayer)
                        .scaleEffect(x: isMirrored ? -1 : 1, y: 1)
                        .clipShape(RoundedRectangle(cornerRadius: Defaults[.mirrorShape] == .rectangle ? MusicPlayerImageSizes.cornerRadiusInset.opened : 100))
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .opacity(camera.isSessionRunning ? 1 : 0)
                }

                if !camera.isSessionRunning {
                    ZStack {
                        RoundedRectangle(cornerRadius: Defaults[.mirrorShape] == .rectangle ? MusicPlayerImageSizes.cornerRadiusInset.opened : 100)
                            .fill(Color(red: 20/255, green: 20/255, blue: 20/255))
                            .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                            .frame(width: geometry.size.width, height: geometry.size.width)
                        VStack(spacing: 8) {
                            Image(systemName: camera.state == .permissionDenied ? "exclamationmark.triangle" : "web.camera")
                                .foregroundStyle(.gray)
                                .font(.system(size: geometry.size.width/3.5))
                            Text(camera.state == .permissionDenied ? "Access Denied" : "Mirror")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .onTapGesture {
                handleCameraTap()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private func handleCameraTap() {
        if isRequestingAuthorization {
            return // Prevent multiple authorization requests
        }
        
        switch webcamManager.refreshAuthorizationStatus() {
        case .authorized:
            if webcamManager.isSessionRunning {
                webcamManager.stopSession()
            } else if webcamManager.cameraAvailable {
                webcamManager.startSession()
            }
        case .permissionDenied:
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Camera Access Required", comment: "Camera permission alert title")
                alert.informativeText = NSLocalizedString("Please allow camera access in System Settings to use the mirror feature.", comment: "Mirror camera permission alert message")
                alert.addButton(withTitle: NSLocalizedString("Open System Settings", comment: "Button title that opens System Settings"))
                alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button title"))

                if alert.runModal() == .alertFirstButtonReturn {
                    if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(settingsURL)
                    }
                }
            }
        case .permissionRequired:
            camera.requestAccess()
        case .requestingPermission, .starting:
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
    CameraPreviewView(camera: CameraModel())
}
