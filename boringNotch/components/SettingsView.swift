    //
    //  SettingsView.swift
    //  boringNotch
    //
    //  Created by Richard Kunkli on 07/08/2024.
    //

import SwiftUI
import LaunchAtLogin
import Sparkle

struct SettingsView: View {
    @EnvironmentObject var vm: BoringViewModel
    let updaterController: SPUStandardUpdaterController
    
    @State private var selectedTab: SettingsEnum = .general
    @State private var showBuildNumber: Bool = false
    let accentColors: [Color] = [.blue, .purple, .pink, .red, .orange, .yellow, .green, .gray]
    
    var body: some View {
        TabView(selection: $selectedTab,
                content:  {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsEnum.general)
            Media()
                .tabItem { Label("Media", systemImage: "play.laptopcomputer") }
                .tag(SettingsEnum.mediaPlayback)
            HUD()
                .tabItem { Label("HUDs", systemImage: "dial.medium.fill") }
                .tag(SettingsEnum.hud)
            Charge()
                .tabItem { Label("Battery", systemImage: "battery.100.bolt") }
                .tag(SettingsEnum.charge)
            Downloads()
                .tabItem { Label("Downloads", systemImage: "square.and.arrow.down") }
                .tag(SettingsEnum.download)
            Shelf()
                .tabItem { Label("Shelf", systemImage: "books.vertical") }
                .tag(SettingsEnum.shelf)
            About()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsEnum.about)
        })
        .formStyle(.grouped)
        .frame(width: 600, height: 500)
        .tint(vm.accentColor)
    }
    
    @ViewBuilder
    func GeneralSettings() -> some View {
        Form {
            Section {
                HStack() {
                    ForEach(accentColors, id: \.self) { color in
                        Button(action: {
                            withAnimation {
                                vm.accentColor = color
                            }
                        }) {
                            Circle()
                                .fill(color)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: vm.accentColor == color ? 2 : 0)
                                        .overlay {
                                            Circle()
                                                .fill(.white)
                                                .frame(width: 7, height: 7)
                                                .opacity(vm.accentColor == color ? 1 : 0)
                                        }
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                    ColorPicker("Custom color", selection: $vm.accentColor)
                        .labelsHidden()
                }
            } header: {
                Text("Accent color")
            }
            
            boringControls()
            
            NotchBehaviour()
        }
    }
    
    @ViewBuilder
    func Charge() -> some View {
        Form {
            Toggle("Show charging indicator", isOn: $vm.chargingInfoAllowed)
            Toggle("Show battery indicator", isOn: $vm.showBattery.animation())
        }
    }
    
    @ViewBuilder
    func Downloads() -> some View {
        Form {
            Section {
                Toggle("Show download progress", isOn: .constant(false))
                    .disabled(true)
                Picker("Download indicator style", selection: $vm.selectedDownloadIndicatorStyle) {
                    Text("Progress bar")
                        .tag(DownloadIndicatorStyle.progress)
                    Text("Percentage")
                        .tag(DownloadIndicatorStyle.percentage)
                }
                .disabled(true)
                Picker("Download icon style", selection: $vm.selectedDownloadIconStyle) {
                    Text("Only app icon")
                        .tag(DownloadIconStyle.onlyAppIcon)
                    Text("Only download icon")
                        .tag(DownloadIconStyle.onlyIcon)
                    Text("Both")
                        .tag(DownloadIconStyle.iconAndAppIcon)
                }
                .disabled(true)
                
            } header: {
                HStack {
                    Text("Download indicators")
                    comingSoonTag()
                }
            }
            Section {
                List {
                    ForEach(0..<1) { _ in
                        Text("No excludes")
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 0) {
                        Button {} label: {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .frame(width: 20, height: 20)
                                .overlay {
                                    Image(systemName: "plus").imageScale(.small)
                                }
                        }
                        Divider()
                        Button {} label: {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .frame(width: 20, height: 20)
                                .overlay {
                                    Image(systemName: "minus").imageScale(.small)
                                }
                        }
                    }
                    .disabled(true)
                    .buttonStyle(PlainButtonStyle())
                }
            } header: {
                HStack (spacing: 4){
                    Text("Exclude apps")
                    comingSoonTag()
                }
                
            }
        }
    }
    
    @ViewBuilder
    func HUD() -> some View {
        Form {
            Section {
                Toggle("Enable HUD replacement", isOn: .constant(false))
                Toggle("Enable glowing effect", isOn: .constant(true))
                Toggle("Use accent color", isOn: .constant(false))
                Toggle("Use album art color during playback", isOn: .constant(false))
            } header: {
                HStack {
                    Text("Customization")
                    comingSoonTag()
                }
            }
            .disabled(true)
        }
    }
    
    @ViewBuilder
    func Media() -> some View {
        Form {
            Section {
                Toggle("Enable colored spectrograms", isOn: $vm.coloredSpectrogram.animation())
                HStack {
                    Stepper(value: $vm.waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(vm.waitInterval, specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Media playback live activity")
            }
        }
        .formStyle(.grouped)}
    
    @ViewBuilder
    func boringControls() -> some View {
        Section {
            
            Toggle("Show cool face animation while inactivity", isOn: $vm.nothumanface.animation())
            LaunchAtLogin.Toggle("Launch at login 🦄")
            Toggle("Enable haptics", isOn: $vm.enableHaptics)
            Toggle("Menubar icon", isOn: $vm.showMenuBarIcon)
            Toggle("Settings icon in notch", isOn: $vm.settingsIconInNotch)
            
        } header: {
            Text("Boring Controls")
        }
    }
    
    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Slider(value: $vm.minimumHoverDuration, in: 0...1, step: 0.1, minimumValueLabel: Text("0"), maximumValueLabel: Text("1")) {
                HStack {
                    Text("Minimum hover duration")
                    Text("\(vm.minimumHoverDuration, specifier: "%.1f")s")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Notch behavior")
        }
    }
    
    @ViewBuilder
    func About() -> some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Release name")
                        Spacer()
                        Text(vm.releaseName)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        if (showBuildNumber) {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "unkown")
                            .foregroundStyle(.secondary)
                            .onTapGesture {
                                withAnimation {
                                    showBuildNumber.toggle()
                                }
                            }
                    }
                } header: {
                    Text("Version info")
                }
                
                UpdaterSettingsView(updater: updaterController.updater)
            }
            Button("Quit boring.notch", role: .destructive) {
                exit(0)
            }
            .padding()
            VStack(spacing: 15) {
                HStack(spacing: 30) {
                    Button {
                        NSWorkspace.shared.open(sponsorPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "cup.and.saucer.fill")
                                .imageScale(.large)
                            Text("Support Us")
                                .foregroundStyle(.blue)
                        }
                        .contentShape(Rectangle())
                    }
                    
                    Button {
                        NSWorkspace.shared.open(productPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                            Text("GitHub")
                                .foregroundStyle(.blue)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(PlainButtonStyle())
                Text("Made with 🫶🏻 by not so boring not.people")
                    .foregroundStyle(.secondary)
                    .padding(.bottom)
            }
        }
    }
    
    @ViewBuilder
    func Shelf() -> some View {
        Form {
            Section {
                Toggle("Enable shelf", isOn: .constant(false))
            } header: {
                comingSoonTag()
            }
            .disabled(true)
        }
    }
    
    func comingSoonTag () -> some View {
        Text("Coming soon")
            .foregroundStyle(.secondary)
            .font(.footnote.bold())
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(Color(nsColor: .secondarySystemFill))
            .clipShape(.capsule)
    }
}
