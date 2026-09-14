//
//  WebcamView.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 19/08/24.
//

import AVFoundation
import Defaults
import SwiftUI

struct WebcamView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager: WebcamManager
    @Default(.isMirrored) private var isMirrored
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let previewLayer = webcamManager.previewLayer {
                    WebcamPreviewLayer(previewLayer: previewLayer)
                        .scaleEffect(x: isMirrored ? -1 : 1, y: 1)
                        .clipShape(RoundedRectangle(cornerRadius: Defaults[.mirrorShape] == .rectangle ? MusicPlayerImageSizes.cornerRadiusInset.opened : 100))
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .opacity(webcamManager.isSessionRunning ? 1 : 0)
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
        if webcamManager.isSessionDesired {
            webcamManager.stopSession()
            return
        }

        switch webcamManager.refreshAuthorizationStatus() {
        case .authorized:
            webcamManager.startSession()
        case .denied, .restricted:
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
        case .notDetermined:
            webcamManager.startSession()
        @unknown default:
            break
        }
    }
}

struct WebcamPreviewLayer: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        Self.attach(previewLayer, to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.attach(previewLayer, to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView.layer as? AVCaptureVideoPreviewLayer)?.removeFromSuperlayer()
        nsView.layer = nil
    }

    static func attach(_ previewLayer: AVCaptureVideoPreviewLayer, to view: NSView) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if view.layer !== previewLayer {
            (view.layer as? AVCaptureVideoPreviewLayer)?.removeFromSuperlayer()
            view.layer = previewLayer
        }
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        CATransaction.commit()
    }
}

#Preview {
    WebcamView(webcamManager: .shared)
}
