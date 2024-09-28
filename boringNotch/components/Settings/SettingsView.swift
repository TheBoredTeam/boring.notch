//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import SwiftUI
import LaunchAtLogin
import Sparkle
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject var vm: BoringViewModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var extensionManager = BoringExtensionManager()
    
    let updaterController: SPUStandardUpdaterController
    
    @State private var selectedTab: SettingsEnum = .general
    @State private var showBuildNumber: Bool = false
    @State private var effectTrigger: Bool = false
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
            Extensions()
                .tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }
                .tag(SettingsEnum.extensions)
            About()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsEnum.about)
        })
        .formStyle(.grouped)
        .tint(vm.accentColor)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
                case .active:
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                case .background, .inactive:
                    NSApp.setActivationPolicy(.accessory)
                    NSApp.deactivate()
                @unknown default:
                    NSApp.setActivationPolicy(.accessory)
                    NSApp.deactivate()
            }
        }
    }
    
    @ViewBuilder
    func GeneralSettings() -> some View {
        Form {
            warningBadge("Your settings will not be restored on restart", "By doing this, we can quickly address global bugs. It will be enabled later on.")
            Section {
                HStack {
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
            
            Section {
                Toggle("Menubar icon", isOn: $vm.showMenuBarIcon)
                LaunchAtLogin.Toggle("Launch at login")
            } header: {
                Text("System features")
            }
            
            boringControls()
            
            NotchBehaviour()
            
            gestureControls()
        }
        
    }
    
    @ViewBuilder
    func Charge() -> some View {
        Form {
            Section {
                Toggle("Show charging indicator", isOn: $vm.chargingInfoAllowed)
                Toggle("Show battery indicator", isOn: $vm.showBattery.animation())
            } header: {
                Text("General")
            }
        }
    }
    
    @ViewBuilder
    func Downloads() -> some View {
        Form {
            warningBadge("We don't support downloads yet", "It will be supported later on.")
            Section {
                Toggle("Show download progress", isOn: $vm.enableDownloadListener).disabled(true)
                Toggle("Enable Safari Downloads", isOn: $vm.enableSafariDownloads).disabled(!vm.enableDownloadListener)
                Picker("Download indicator style", selection: $vm.selectedDownloadIndicatorStyle) {
                    Text("Progress bar")
                        .tag(DownloadIndicatorStyle.progress)
                    Text("Percentage")
                        .tag(DownloadIndicatorStyle.percentage)
                }
                Picker("Download icon style", selection: $vm.selectedDownloadIconStyle) {
                    Text("Only app icon")
                        .tag(DownloadIconStyle.onlyAppIcon)
                    Text("Only download icon")
                        .tag(DownloadIconStyle.onlyIcon)
                    Text("Both")
                        .tag(DownloadIconStyle.iconAndAppIcon)
                }
                
            } header: {
                HStack {
                    Text("Download indicators")
                    comingSoonTag()
                }
            }
            Section {
                List {
                    ForEach([].indices, id: \.self) { index in
                        Text("\(index)")
                    }
                }
                .frame(minHeight: 96)
                .overlay {
                    if true {
                        Text("No excluded apps")
                            .foregroundStyle(Color(.secondaryLabelColor))
                    }
                }
                .actionBar {
                    Button {
                        
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 20, height: 15, alignment: .center)
                            .contentShape(Rectangle())
                    }
                    
                    Divider()
                    Button {
                        
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 20, height: 15, alignment: .center)
                            .contentShape(Rectangle())
                    }
                }
                .onDeleteCommand {
                    //
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
                Toggle("Enable HUD replacement", isOn: $vm.hudReplacement)
            } header: {
                Text("General")
            }
            Section {
                Picker("HUD style", selection: $vm.inlineHUD.animation()) {
                    Text("Default")
                        .tag(false)
                    Text("Inline")
                        .tag(true)
                }
                .onChange(of: vm.inlineHUD) { _, newValue in
                    if newValue {
                        withAnimation {
                            vm.systemEventIndicatorShadow = false
                            vm.enableGradient = false
                        }
                    }
                }
                Picker("Progressbar style", selection: $vm.enableGradient.animation()) {
                    Text("Hierarchical")
                        .tag(false)
                    Text("Gradient")
                        .tag(true)
                }
                Toggle("Enable glowing effect", isOn: $vm.systemEventIndicatorShadow.animation())
                Toggle("Use accent color", isOn: $vm.systemEventIndicatorUseAccent.animation())
            } header: {
                HStack {
                    Text("Appearance")
                }
            }
        }
        .disabled(extensionManager.installedExtensions.map({$0.bundleIdentifier}).contains(hudExtension))
    }
    
    @ViewBuilder
    func Media() -> some View {
        Form {
            Section {
                Toggle("Enable colored spectrograms", isOn: $vm.coloredSpectrogram.animation())
                Toggle("Enable sneak peek", isOn: $vm.enableSneakPeek)
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
            
            Section {
                Toggle("Autohide BoringNotch in fullscreen", isOn: $vm.enableFullscreenMediaDetection)
            } header: {
                HStack {
                    Text("Fullscreen media playback detection")
                    customBadge(text: "Beta")
                }
            }
        }
    }
    
    @ViewBuilder
    func boringControls() -> some View {
        Section {
            Picker("Button icon style", selection: $vm.showEmojis) {
                Text("Emoji")
                    .tag(true)
                Text("Symbols")
                    .tag(false)
            }
            Toggle("Show cool face animation while inactivity", isOn: $vm.nothumanface.animation())
            Toggle("Always show tabs", isOn: $vm.alwaysShowTabs)
            Toggle(isOn: $vm.openLastTabByDefault) {
                Text("Remember last tab")
                if vm.openShelfByDefault && vm.openLastTabByDefault {
                    Text("""
                         Note: If files are in the shelf, the shelf will always be opened by default because "Open shelf tab by default if items added" is enabled. You can change this in the shelf settings.
                         """)
                }
            }
            .disabled(!vm.alwaysShowTabs)
            Toggle("Enable boring mirror", isOn: $vm.showMirror)
            Picker("Mirror shape", selection: $vm.mirrorShape) {
                Text("Circle")
                    .tag(MirrorShapeEnum.circle)
                Text("Square")
                    .tag(MirrorShapeEnum.rectangle)
            }
            Toggle("Settings icon in notch", isOn: $vm.settingsIconInNotch)
        } header: {
            Text("Boring Controls")
        }
    }
    
    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Toggle("Enable gestures", isOn: $vm.enableGestures.animation())
                .disabled(!vm.openNotchOnHover)
            if vm.enableGestures {
                Toggle("Media change with horizontal gestures", isOn: .constant(false))
                    .disabled(true)
                Toggle("Close gesture", isOn: $vm.closeGestureEnabled)
                Slider(value: $vm.gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(vm.gestureSensitivity == 100 ? "High" : vm.gestureSensitivity == 200 ? "Medium" : "Low")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Gesture control")
                customBadge(text: "Beta")
            }
        }
    }
    
    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Toggle("Enable haptics", isOn: $vm.enableHaptics)
            Toggle("Enable shadow", isOn: $vm.enableShadow)
            Toggle("Corner radius scaling", isOn: $vm.cornerRadiusScaling)
            Toggle("Open notch on hover", isOn: $vm.openNotchOnHover.animation())
                .onChange(of: vm.openNotchOnHover) { old, new in
                    if !new {
                        vm.enableGestures = true
                    }
                }
            if vm.openNotchOnHover {
                Slider(value: $vm.minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Minimum hover duration")
                        Spacer()
                        Text("\(vm.minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
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
                Toggle("Enable shelf", isOn: $vm.boringShelf)
                Toggle("Open shelf tab by default if items added", isOn: $vm.openShelfByDefault)
            } header: {
                HStack {
                    Text("General")
                }
            }
        }
    }
    
    @ViewBuilder
    func Extensions() -> some View {
        ScrollView {
            Form {
                Section {
                    List {
                        ForEach(extensionManager.installedExtensions.indices, id: \.self) { index in
                            let item = extensionManager.installedExtensions[index]
                            HStack {
                                AppIcon(for: item.bundleIdentifier)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                Text(item.name)
                                ListItemPopover {
                                    Text("Description")
                                }
                                Spacer(minLength: 0)
                                HStack(spacing: 6) {
                                    Circle()
                                        .frame(width: 6, height: 6)
                                        .foregroundColor(isExtensionRunning(item.bundleIdentifier) ? .green : item.status == .disabled ? .gray : .red)
                                        .conditionalModifier(isExtensionRunning(item.bundleIdentifier)) { view in
                                            view
                                                .shadow(color: .green, radius: 3)
                                        }
                                    Text(isExtensionRunning(item.bundleIdentifier) ? "Running" : item.status == .disabled ? "Disabled" : "Stopped")
                                        .contentTransition(.numericText())
                                        .foregroundStyle(.secondary)
                                        .font(.footnote)
                                }
                                .frame(width: 60, alignment: .leading)
                                
                                Menu(content: {
                                    Button("Restart") {
                                        let ws = NSWorkspace.shared
                                        
                                        if let ext = ws.runningApplications.first(where: {$0.bundleIdentifier == item.bundleIdentifier}) {
                                            ext.terminate()
                                        }
                                        
                                        if let appURL = ws.urlForApplication(withBundleIdentifier: item.bundleIdentifier) {
                                            ws.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
                                        }
                                    }
                                    .keyboardShortcut("R", modifiers: .command)
                                    Button("Disable") {
                                        if let ext = NSWorkspace.shared.runningApplications.first(where: {$0.bundleIdentifier == item.bundleIdentifier}) {
                                            ext.terminate()
                                        }
                                        extensionManager.installedExtensions[index].status = .disabled
                                    }
                                    .keyboardShortcut("D", modifiers: .command)
                                    Divider()
                                    Button("Uninstall", role: .destructive) {
                                        //
                                    }
                                }, label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(.secondary)
                                })
                                .controlSize(.regular)
                                
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.vertical, 5)
                        }
                    }
                    .frame(minHeight: 120)
                    .actionBar {
                        Button {
                            
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                Text("Add manually")
                            }
                            .foregroundStyle(.secondary)
                        }
                        .disabled(true)
                        Spacer()
                        Button {
                            withAnimation(.linear(duration: 1)) {
                                effectTrigger.toggle()
                            } completion: {
                                effectTrigger.toggle()
                            }
                            extensionManager.checkIfExtensionsAreInstalled()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .rotationEffect(effectTrigger ? .degrees(360) : .zero)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(PlainButtonStyle())
                    .overlay {
                        if extensionManager.installedExtensions.isEmpty {
                            Text("No extension installed")
                                .foregroundStyle(Color(.secondaryLabelColor))
                        }
                    }
                } header: {
                    HStack(spacing: 0) {
                        Text("Installed extensions")
                        if !extensionManager.installedExtensions.isEmpty {
                            Text(" – \(extensionManager.installedExtensions.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            //TipsView()
                //.padding(.horizontal, 19)
            
            Form {
                Section {
                    KeyboardShortcuts.Recorder("Clipboard history panel shortcut", name: .clipboardHistoryPanel)
                } header: {
                    HStack {
                        Text("Clipboard history")
                        proFeatureBadge()
                    }
                }
                .disabled(extensionManager.installedExtensions.map({$0.bundleIdentifier}).contains(clipboardExtension))
            }
        }
    }
    
    func proFeatureBadge() -> some View {
        Text("Upgrade to Pro")
            .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
            .font(.footnote.bold())
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
    }
    
    func comingSoonTag() -> some View {
        Text("Coming soon")
            .foregroundStyle(.secondary)
            .font(.footnote.bold())
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(Color(nsColor: .secondarySystemFill))
            .clipShape(.capsule)
    }
    
    func customBadge(text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .font(.footnote.bold())
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(Color(nsColor: .secondarySystemFill))
            .clipShape(.capsule)
    }
    
    func warningBadge(_ text: String, _ description: String) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading) {
                    Text(text)
                        .font(.headline)
                    Text(description)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}
