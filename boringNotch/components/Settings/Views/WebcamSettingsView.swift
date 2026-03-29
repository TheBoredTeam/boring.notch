//
//  WebcamSettingsView.swift
//  boringNotch
//
//  Created by Anmol Malhotra on 2026-02-24.
//

import AVFoundation
import SwiftUI
import Defaults

struct MirrorSettings: View {
    @Default(.showMirror) private var showMirror
    @Default(.isMirrored) private var isMirrored
    @Default(.mirrorShape) private var mirrorShape
    @ObservedObject private var webcamManager = WebcamManager.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showMirror) {
                    Text("Enable boring mirror")
                }
                .disabled(!checkVideoInput())

                Defaults.Toggle(key: .isMirrored) {
                    Text("Mirror video")
                }
                .disabled(!showMirror || !checkVideoInput())

                Picker("Mirror camera", selection: Binding(
                    get: { webcamManager.selectedCameraID },
                    set: { webcamManager.setSelectedCamera(id: $0) }
                )) {
                    Text("Automatic")
                        .tag(nil as String?)
                    ForEach(webcamManager.availableCameras, id: \.uniqueID) { camera in
                        Text(camera.localizedName)
                            .tag(Optional(camera.uniqueID))
                    }
                }
                .disabled(!showMirror || !checkVideoInput())

                Picker("Mirror shape", selection: $mirrorShape) {
                    Text("Circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("Square")
                        .tag(MirrorShapeEnum.rectangle)
                }
                .disabled(!showMirror || !checkVideoInput())
            } header: {
                Text("Mirror")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Mirror")
        .onAppear {
            webcamManager.checkCameraAvailability()
        }
    }

    private func checkVideoInput() -> Bool {
        AVCaptureDevice.default(for: .video) != nil
    }
}
