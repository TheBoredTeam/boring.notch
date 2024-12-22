//
//  WebcamView.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 19/08/24.
//

import AVFoundation
import SwiftUI
import Defaults

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
                            Image(systemName: "web.camera")
                                .foregroundStyle(.gray)
                                .font(.system(size: geometry.size.width/3.5))
                            Text("common.mirror")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .onTapGesture {
                if webcamManager.isSessionRunning {
                    webcamManager.stopSession()
                } else {
                    webcamManager.startSession()
                }
            }
            .onDisappear {
                webcamManager.stopSession()
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
