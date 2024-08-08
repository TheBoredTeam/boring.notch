//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import SwiftUI
import LaunchAtLogin

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
        VStack{
            Form {
                Section {
                    Toggle("Enable colored spectrograms", isOn: $vm.coloredSpectrogram.animation())
                    TextField("Media inactivity timeout", value: $vm.waitInterval, formatter: NumberFormatter())
                } header: {
                    Text("Media playback live activity")
                }
                boringControls()
            }
            .formStyle(.grouped)
            
            Text(vm.releaseName).font(.title2).padding()
        }
    }
    
    @ViewBuilder
    func boringControls() -> some View {
        Section {
            Toggle("Show cool face animation while inactivity", isOn: $vm.nothumanface.animation())
            Toggle("Show battery indicator", isOn: $vm.showBattery.animation())
            LaunchAtLogin.Toggle("Launch at login 🦄")
        } header: {
            Text("Boring Controls")
        }
    }
}

#Preview {
    SettingsView().environmentObject(BoringViewModel())
}
