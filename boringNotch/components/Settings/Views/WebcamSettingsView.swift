//
//  WebcamSettingsView.swift
//  boringNotch
//
//  Created by Anmol Malhotra on 2026-02-24.
//

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
                .disabled(!camera.cameraAvailable)

                Defaults.Toggle(key: .isMirrored) {
                    Text("Flip video")
                }
                .disabled(!showMirror || !camera.cameraAvailable)

                Picker("Camera", selection: Binding(
                    get: { camera.selection },
                    set: { camera.selectCamera($0) }
                )) {
                    Text("Automatic")
                        .tag(CameraSelection.automatic)
                    ForEach(camera.availableCameras) { device in
                        Text(device.name)
                            .tag(CameraSelection.device(device.id))
                    }
                }
                .disabled(!showMirror || !camera.cameraAvailable)

                Picker("Frame shape", selection: $mirrorShape) {
                    Text("Circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("Square")
                        .tag(MirrorShapeEnum.rectangle)
                }
                .disabled(!showMirror || !camera.cameraAvailable)
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
}
