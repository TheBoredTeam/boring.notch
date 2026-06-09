//
//  AudioDeviceMenu.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-09.
//
//  Quick output-device switcher shown in the open notch header.
//

import SwiftUI

struct AudioDeviceMenu: View {
    @ObservedObject var audioManager = AudioDeviceManager.shared

    var body: some View {
        Menu {
            ForEach(audioManager.outputDevices) { device in
                Button {
                    audioManager.setDefaultOutput(device.id)
                } label: {
                    Label(
                        device.name,
                        systemImage: device.id == audioManager.currentDeviceID
                            ? "checkmark" : device.iconName
                    )
                }
            }
        } label: {
            Capsule()
                .fill(.black)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: audioManager.currentDeviceIcon)
                        .foregroundColor(.white)
                        .imageScale(.medium)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30, height: 30)
        .fixedSize()
        .onAppear { audioManager.reload() }
    }
}
