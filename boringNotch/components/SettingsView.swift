//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import SwiftUI
import LaunchAtLogin

struct SettingsView: View {
    @EnvironmentObject var vm: BoringViewModel
    @State private var selectedTab: SettingsEnum = .general
    var body: some View {
        TabView(selection: $selectedTab,
                content:  {
            GeneralSettings().tabItem { Label("General", systemImage: "gear") }.tag(SettingsEnum.general)
        })
    }
    
    @ViewBuilder
    func GeneralSettings() -> some View {
        VStack{
            Form {
                Section {
                    Toggle("Enable colored spectrograms", isOn: $vm.coloredSpectrogram.animation())
                    HStack {
                    Text("Media inactivity timeout")
                    Spacer()
                    TextField("Media inactivity timeout", value: $vm.waitInterval, formatter: NumberFormatter())
                        .labelsHidden()
                        .frame(width: 25)
                        .multilineTextAlignment(.trailing)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }
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
