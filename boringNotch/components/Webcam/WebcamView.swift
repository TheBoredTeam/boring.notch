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
    let camera: CameraModel
    @Default(.isMirrored) private var isMirrored

    private static let mirrorSide: CGFloat = 130

    private static var mirrorCornerRadius: CGFloat {
        Defaults[.mirrorShape] == .rectangle ? MusicPlayerImageSizes.cornerRadiusInset.opened : mirrorSide / 2
    }

    var body: some View {
        ZStack {
            if let session = camera.activeSession {
                CameraPreviewLayerView(
                    session: session,
                    isMirrored: isMirrored
                )
                .frame(width: Self.mirrorSide, height: Self.mirrorSide)
                .clipShape(RoundedRectangle(cornerRadius: Self.mirrorCornerRadius))
                .opacity(camera.isSessionRunning ? 1 : 0)
            }

            if !camera.isSessionRunning {
                ZStack {
                    RoundedRectangle(cornerRadius: Self.mirrorCornerRadius)
                        .fill(Color(red: 20/255, green: 20/255, blue: 20/255))
                        .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                        .frame(width: Self.mirrorSide, height: Self.mirrorSide)
                    VStack(spacing: 8) {
                        Image(systemName: camera.state == .permissionDenied ? "exclamationmark.triangle" : "web.camera")
                            .foregroundStyle(.gray)
                            .font(.system(size: Self.mirrorSide / 3.5))
                        Text(mirrorPlaceholderTitle)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .frame(width: Self.mirrorSide, height: Self.mirrorSide)
        .onTapGesture {
            handleCameraTap()
        }
    }

    private var mirrorPlaceholderTitle: String {
        switch camera.state {
        case .permissionDenied:
            NSLocalizedString("Access Denied", comment: "Camera permission placeholder title")
        case .interrupted:
            NSLocalizedString("Paused", comment: "Camera interrupted placeholder title")
        case .unavailable:
            NSLocalizedString("No Camera", comment: "No camera available placeholder title")
        default:
            NSLocalizedString("Mirror", comment: "Camera mirror placeholder title")
        }
    }

    private func handleCameraTap() {
        switch camera.state {
        case .running, .interrupted:
            camera.stopSession()
        case .stopped, .unavailable, .failed:
            if camera.cameraAvailable {
                camera.startSession()
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

/// AppKit-native preview: owns its own `AVCaptureVideoPreviewLayer` as a
/// sublayer and keeps mirroring at the capture-connection level so SwiftUI
/// transforms are not involved.
struct CameraPreviewLayerView: NSViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.attach(session: session, isMirrored: isMirrored)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.attach(session: session, isMirrored: isMirrored)
    }

    func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: ()) {
        nsView.detach()
    }
}

final class CameraPreviewNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // The backing layer must exist before `attach` adds the preview
        // sublayer, otherwise addSublayer silently no-ops and nothing renders.
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Re-apply in case the view was moved into a window after attaching;
        // also fixes frames set while detached.
        if previewLayer != nil {
            layoutPreview()
        }
    }

    override func layout() {
        super.layout()
        layoutPreview()
    }

    func attach(session: AVCaptureSession, isMirrored: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if let previewLayer, previewLayer.session === session {
            applyMirroring(isMirrored, to: previewLayer)
            layoutPreview()
            return
        }

        previewLayer?.removeFromSuperlayer()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.frame = bounds
        self.layer?.addSublayer(layer)
        previewLayer = layer

        applyMirroring(isMirrored, to: layer)
    }

    func detach() {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    private func layoutPreview() {
        guard let previewLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }

    /// Mirroring belongs to the capture connection, not the view hierarchy.
    private func applyMirroring(_ isMirrored: Bool, to layer: AVCaptureVideoPreviewLayer) {
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            // Preview connections are front-facing-mirrored by default; align
            // the presentation with the user's "Flip video" preference.
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isMirrored
        }
    }
}

#Preview {
    CameraPreviewView(camera: CameraModel())
}
