//
//  WebcamSettingsView.swift
//  boringNotch
//
//  Created by Anmol Malhotra on 2026-02-24.
//

import AVFoundation
import SwiftUI
import Defaults

struct WebcamSettingsView: View {
    @Default(.showMirror) private var showMirror
    @Default(.isMirrored) private var isMirrored
    @Default(.mirrorShape) private var mirrorShape
    let camera: CameraModel

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showMirror) {
                    Text("Enable boring mirror")
                }
                .disabled(!checkVideoInput())

                Defaults.Toggle(key: .isMirrored) {
                    Text("Flip video")
                }
                .disabled(!showMirror || !checkVideoInput())

                Picker("Camera", selection: Binding(
                    get: { camera.selectedCameraID },
                    set: { camera.selectCamera($0) }
                )) {
                    Text("Automatic")
                        .tag(nil as String?)
                    ForEach(camera.availableCameras) { camera in
                        Text(camera.name)
                            .tag(camera.id as String?)
                    }
                }
                .disabled(!showMirror || !checkVideoInput())

                Picker("Frame shape", selection: $mirrorShape) {
                    Text("Circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("Square")
                        .tag(MirrorShapeEnum.rectangle)
                }
                .disabled(!showMirror || !checkVideoInput())
            } header: {
                Text("General")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Mirror")
        .onAppear {
            camera.refresh()
        }
    }

    private func checkVideoInput() -> Bool {
        AVCaptureDevice.default(for: .video) != nil
    }
}
