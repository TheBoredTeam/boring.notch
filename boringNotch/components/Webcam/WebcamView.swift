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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let previewLayer = webcamManager.previewLayer {
                    CameraPreviewLayerView(previewLayer: previewLayer)
                        .scaleEffect(x: -1, y: 1)
                        .clipShape(RoundedRectangle(cornerRadius: Defaults[.mirrorShape] == .rectangle ? !Defaults[.cornerRadiusScaling] ? MusicPlayerImageSizes.cornerRadiusInset.closed : MusicPlayerImageSizes.cornerRadiusInset.opened : 100))
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .opacity(webcamManager.isSessionRunning ? 1 : 0)
                }

                if !webcamManager.isSessionRunning {
                    ZStack {
                        RoundedRectangle(cornerRadius: Defaults[.mirrorShape] == .rectangle ? !Defaults[.cornerRadiusScaling] ? MusicPlayerImageSizes.cornerRadiusInset.closed : 12 : 100)
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
                switch webcamManager.authorizationStatus {
                case .authorized:
                    if webcamManager.isSessionRunning {
                        webcamManager.stopSession()
                    } else {
                        webcamManager.startSession()
                    }
                case .denied, .restricted:
                    print("🚫 Camera access denied/restricted from \(#file):\(#line)")
                    let alert = NSAlert()
                    alert.messageText = "Camera Access Required"
                    alert.informativeText = "Please allow camera access in System Settings to use the mirror feature."
                    alert.addButton(withTitle: "Open Settings")
                    alert.addButton(withTitle: "Cancel")

                    if alert.runModal() == .alertFirstButtonReturn {
                        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                case .notDetermined:
                    print("🎥 Checking camera authorization from \(#file):\(#line)")
                    webcamManager.checkAndRequestVideoAuthorization()
                @unknown default:
                    break
                }
            }
            .onDisappear {
                webcamManager.cleanup()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct CameraPreviewLayerView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        previewLayer.frame = view.bounds
        view.layer = previewLayer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        previewLayer.frame = nsView.bounds
    }
}

#Preview {
    CameraPreviewView(webcamManager: WebcamManager())
}
