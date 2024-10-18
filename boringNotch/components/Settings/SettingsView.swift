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
import Defaults
import SwiftUIIntrospect

struct SettingsView: View {
    @EnvironmentObject var vm: BoringViewModel
    @Environment(\.scenePhase) private var scenePhase
    let updaterController: SPUStandardUpdaterController
    
    @State private var selectedTab = "General"
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(destination: GeneralSettings(), isActive: .constant(selectedTab == "General")) {
                    Label("General", systemImage: "gear")
                }
                NavigationLink(destination: Media()) {
                    Label("Media", systemImage: "play.laptopcomputer")
                }
                NavigationLink(destination: HUD()) {
                    Label("HUDs", systemImage: "dial.medium.fill")
                }
                NavigationLink(destination: Charge()) {
                    Label("Battery", systemImage: "battery.100.bolt")
                }
                NavigationLink(destination: Downloads()) {
                    Label("Downloads", systemImage: "square.and.arrow.down")
                }
                NavigationLink(destination: Shelf()) {
                    Label("Shelf", systemImage: "books.vertical")
                }
                NavigationLink(destination: Extensions()) {
                    Label("Extensions", systemImage: "puzzlepiece.extension")
                }
                NavigationLink(
                    destination: About(updaterController: updaterController)
                ) {
                    Label("About", systemImage: "info.circle")
                }
            }
            .tint(Defaults[.accentColor])
        } detail: {
            GeneralSettings()
                .navigationSplitViewColumnWidth(500)
        }
        .formStyle(.grouped)
        .introspect(.window, on: .macOS(.v14, .v15)) { window in
            window.toolbarStyle = .unified
        }
    }
}

struct GeneralSettings: View {
    @State private var screens: [String] = NSScreen.screens.compactMap({$0.localizedName})
    let accentColors: [Color] = [.blue, .purple, .pink, .red, .orange, .yellow, .green, .gray]
    @EnvironmentObject var vm: BoringViewModel
    @Default(.accentColor) var accentColor
    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    
    var body: some View {
        Form {
            Section {
                HStack {
                    ForEach(accentColors, id: \.self) { color in
                        Button(action: {
                            withAnimation {
                                Defaults[.accentColor] = color
                            }
                        }) {
                            Circle()
                                .fill(color)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: Defaults[.accentColor] == color ? 2 : 0)
                                        .overlay {
                                            Circle()
                                                .fill(.white)
                                                .frame(width: 7, height: 7)
                                                .opacity(Defaults[.accentColor] == color ? 1 : 0)
                                        }
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                    ColorPicker("Custom color", selection: $accentColor)
                        .labelsHidden()
                }
            } header: {
                Text("Accent color")
            }
            
            Section {
                Defaults.Toggle("Menubar icon", key: .menubarIcon)
                LaunchAtLogin.Toggle("Launch at login")
                Picker("Show on a specific display", selection: $vm.selectedScreen) {
                    ForEach(screens, id: \.self) { screen in
                        Text(screen)
                    }
                }
                .onChange(of: NSScreen.screens) { old, new in
                    screens = new.compactMap({$0.localizedName})
                }
            } header: {
                Text("System features")
            }
            
            boringControls()
            
            NotchBehaviour()
            
            gestureControls()
        }
        .tint(Defaults[.accentColor])
        .toolbar {
            Button("Quit app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .navigationTitle("General")
    }
    
    @ViewBuilder
    func boringControls() -> some View {
        Section {
            Picker("Button icon style", selection: $showEmojis) {
                Text("Emoji")
                    .tag(true)
                Text("Symbols")
                    .tag(false)
            }
            Defaults.Toggle("Show cool face animation while inactivity", key: .showNotHumanFace)
            Toggle("Always show tabs", isOn: $vm.alwaysShowTabs)
            Toggle("Remember last tab", isOn: $vm.openLastTabByDefault)
            Defaults.Toggle("Enable boring mirror", key: .showMirror)
            Picker("Mirror shape", selection: $mirrorShape) {
                Text("Circle")
                    .tag(MirrorShapeEnum.circle)
                Text("Square")
                    .tag(MirrorShapeEnum.rectangle)
            }
            Defaults.Toggle("Settings icon in notch", key: .settingsIconInNotch)
            Defaults.Toggle("Enable blur effect behind album art", key: .lightingEffect)
            Defaults.Toggle("Show calendar", key: .showCalendar)
        } header: {
            Text("Boring Controls")
        }
    }
    
    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle("Enable gestures", key: .enableGestures)
                .disabled(!Defaults[.openNotchOnHover])
            if Defaults[.enableGestures] {
                Toggle("Media change with horizontal gestures", isOn: .constant(false))
                    .disabled(true)
                Defaults.Toggle("Close gesture", key: .closeGestureEnabled)
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(Defaults[.gestureSensitivity] == 100 ? "High" : Defaults[.gestureSensitivity] == 200 ? "Medium" : "Low")
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
            Defaults.Toggle("Enable haptics", key: .enableHaptics)
            Defaults.Toggle("Enable shadow", key: .enableShadow)
            Defaults.Toggle("Corner radius scaling", key: .cornerRadiusScaling)
            Defaults.Toggle("Open notch on hover", key: .openNotchOnHover)
            if Defaults[.openNotchOnHover] {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Minimum hover duration")
                        Spacer()
                        Text("\(Defaults[.minimumHoverDuration], specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Notch behavior")
        }
    }
}

struct Charge: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle("Show charging indicator", key: .chargingInfoAllowed)
                Defaults.Toggle("Show battery indicator", key: .showBattery)
            } header: {
                Text("General")
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("Battery")
    }
}

struct Downloads: View {
    @Default(.selectedDownloadIndicatorStyle) var selectedDownloadIndicatorStyle
    @Default(.selectedDownloadIconStyle) var selectedDownloadIconStyle
    var body: some View {
        Form {
            warningBadge("We don't support downloads yet", "It will be supported later on.")
            Section {
                Defaults.Toggle("Show download progress", key: .enableDownloadListener)
                    .disabled(true)
                Defaults.Toggle("Enable Safari Downloads", key: .enableSafariDownloads)
                    .disabled(!Defaults[.enableDownloadListener])
                Picker("Download indicator style", selection: $selectedDownloadIndicatorStyle) {
                    Text("Progress bar")
                        .tag(DownloadIndicatorStyle.progress)
                    Text("Percentage")
                        .tag(DownloadIndicatorStyle.percentage)
                }
                Picker("Download icon style", selection: $selectedDownloadIconStyle) {
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
                .actionBar(padding: 0) {
                    Group {
                        Button {
                            
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 25, height: 16, alignment: .center)
                                .contentShape(Rectangle())
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                        Button {
                            
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 20, height: 16, alignment: .center)
                                .contentShape(Rectangle())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack (spacing: 4){
                    Text("Exclude apps")
                    comingSoonTag()
                }
                
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("Downloads")
    }
}

struct HUD: View {
    @EnvironmentObject var vm: BoringViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    var body: some View {
        Form {
            Section {
                Toggle("Enable HUD replacement", isOn: $vm.hudReplacement)
            } header: {
                Text("General")
            }
            Section {
                Picker("HUD style", selection: $inlineHUD) {
                    Text("Default")
                        .tag(false)
                    Text("Inline")
                        .tag(true)
                }
                .onChange(of: Defaults[.inlineHUD]) { _, newValue in
                    if newValue {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }
                Picker("Progressbar style", selection: $enableGradient) {
                    Text("Hierarchical")
                        .tag(false)
                    Text("Gradient")
                        .tag(true)
                }
                Defaults.Toggle("Enable glowing effect", key: .systemEventIndicatorShadow)
                Defaults.Toggle("Use accent color", key: .systemEventIndicatorUseAccent)
            } header: {
                HStack {
                    Text("Appearance")
                }
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("HUDs")
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    var body: some View {
        Form {
            Section {
                Defaults.Toggle("Enable colored spectrograms", key: .coloredSpectrogram)
                Defaults.Toggle("Enable sneak peek", key: .enableSneakPeek)
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Media playback live activity")
            }
            
            Section {
                Defaults.Toggle("Autohide BoringNotch in fullscreen", key: .enableFullscreenMediaDetection)
            } header: {
                HStack {
                    Text("Fullscreen media playback detection")
                    customBadge(text: "Beta")
                }
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("Media")
    }
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Release name")
                        Spacer()
                        Text(Defaults[.releaseName])
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
                    }
                    .onTapGesture {
                        withAnimation {
                            showBuildNumber.toggle()
                        }
                    }
                } header: {
                    Text("Version info")
                }
                
                UpdaterSettingsView(updater: updaterController.updater)
            }
            Button("Open welcome window") {
                openWindow(id: "onboarding")
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
        .tint(Defaults[.accentColor])
        .navigationTitle("About")
    }
}

struct Shelf: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle("Enable shelf", key: .boringShelf)
                Defaults.Toggle("Open shelf tab by default if items added", key: .openShelfByDefault)
            } header: {
                HStack {
                    Text("General")
                }
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("Shelf")
    }
}

struct Extensions: View {
    @StateObject var extensionManager = BoringExtensionManager()
    @State private var effectTrigger: Bool = false
    var body: some View {
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
                            .padding(.bottom, 22)
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
        .tint(Defaults[.accentColor])
        .navigationTitle("Extensions")
        //TipsView()
        //.padding(.horizontal, 19)
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
