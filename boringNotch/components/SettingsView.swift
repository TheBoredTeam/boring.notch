//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import SwiftUI

enum settingsEnum {
    case general
}

struct SettingsView: View {
    @EnvironmentObject var vm: BoringViewModel
    @State private var selectedTab: settingsEnum = .general
    var body: some View {
        TabView(selection: $selectedTab,
                content:  {
            GeneralSettings().tabItem { Label("General", systemImage: "gear") }.tag(settingsEnum.general)
        })
    }
    
    @ViewBuilder
    func GeneralSettings() -> some View {
        Form {
            Section {
                Toggle("Enable colored spectrograms", isOn: $vm.coloredSpectrogram.animation())
                TextField("Media inactivity timeout", value: $vm.waitInterval, formatter: NumberFormatter())
            } header: {
                Text("Media playback live activity")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
}
