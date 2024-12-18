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
import AVFoundation
import LottieUI

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        
        let updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        
        SettingsView(extensionManager: BoringExtensionManager(), updaterController: updaterController)
            .previewLayout(.sizeThatFits)
            .padding()
    }
}

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var extensionManager = BoringExtensionManager()
    let updaterController: SPUStandardUpdaterController
    
    @State private var selectedTab = "General"
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(destination: GeneralSettings()) {
                    Label("settings.tab.general", systemImage: "gear")
                }
                NavigationLink(destination: Appearance()) {
                    Label("settings.tab.appearance", systemImage: "eye")
                }
                NavigationLink(destination: Media()) {
                    Label("settings.tab.media", systemImage: "play.laptopcomputer")
                }
                if extensionManager.installedExtensions
                    .contains(
                        where: { $0.bundleIdentifier == hudExtension
                        }) {
                    NavigationLink(destination: HUD()) {
                        Label("settings.tab.huds", systemImage: "dial.medium.fill")
                    }
                }
                NavigationLink(destination: Charge()) {
                    Label("settings.tab.battery", systemImage: "battery.100.bolt")
                }
                if extensionManager.installedExtensions
                    .contains(
                        where: { $0.bundleIdentifier == downloadManagerExtension
                        }) {
                    NavigationLink(destination: Downloads()) {
                        Label("settings.tab.downloads", systemImage: "square.and.arrow.down")
                    }
                }
                NavigationLink(destination: Shelf()) {
                    Label("settings.tab.shelf", systemImage: "books.vertical")
                }
                NavigationLink(destination: Shortcuts()) {
                    Label("settings.tab.shortcuts", systemImage: "keyboard")
                }
                NavigationLink(destination: Extensions()) {
                    Label("settings.tab.extensions", systemImage: "puzzlepiece.extension")
                }
                NavigationLink(
                    destination: About(updaterController: updaterController)
                ) {
                    Label("settings.tab.about", systemImage: "info.circle")
                }
            }
            .tint(Defaults[.accentColor])
        } detail: {
            GeneralSettings()
        }
        .environmentObject(extensionManager)
        .formStyle(.grouped)
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
        .introspect(.window, on: .macOS(.v14, .v15)) { window in
            window.toolbarStyle = .unified
            window.styleMask.update(with: .resizable)
        }
    }
}

struct GeneralSettings: View {
    @State private var screens: [String] = NSScreen.screens.compactMap({$0.localizedName})
    let accentColors: [Color] = [.blue, .purple, .pink, .red, .orange, .yellow, .green, .gray]
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.accentColor) var accentColor
    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    //@State var nonNotchHeightMode: NonNotchHeightMode = .matchRealNotchSize
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover

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
                    ColorPicker("settings.general.accent_color.custom_color", selection: $accentColor)
                        .labelsHidden()
                }
            } header: {
                Text("settings.general.header.accent_color")
            }

            Section {
                Defaults.Toggle(
                    NSLocalizedString("settings.general.menubar_icon", comment: "Toggle in parameter to enable menubar icon"),
                    key: .menubarIcon
                )
                LaunchAtLogin.Toggle(
                    NSLocalizedString("settings.general.launch_at_login", comment:"Toggle for parameter launch at login")
                )
                Defaults.Toggle(key: .showOnAllDisplays) {
                    HStack {
                        Text("settings.general.show_on_all_displays")
                        customBadge(text: NSLocalizedString("common.beta", comment: "Beta badge"))
                    }
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                Picker("settings.general.show_on_specific_display", selection: $coordinator.preferredScreen) {
                    ForEach(screens, id: \.self) { screen in
                        Text(screen)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens =  NSScreen.screens.compactMap({$0.localizedName})
                }
            } header: {
                Text("settings.general.header.system_features")
            }
            
            Section {
                Picker(selection: $notchHeightMode, label:
                HStack {
                    Text("settings.general.notch_display_height")
                    customBadge(text: NSLocalizedString("common.beta", comment: "Beta badge"))
                }) {
                    Text("settings.general.notch_match_display_height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("settings.general.notch_match_menubar_height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("settings.general.notch_custom_height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: notchHeightMode) {
                    switch notchHeightMode {
                    case .matchRealNotchSize:
                            notchHeight = 38
                        case .matchMenuBar:
                            notchHeight = 44
                        case .custom:
                            nonNotchHeight = 38
                    }
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
                if notchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 15...45, step: 1) {
                        Text("settings.general.custom_notch_size \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("settings.general.non_notch_display_height", selection: $nonNotchHeightMode) {
                    Text("settings.general.notch_match_menubar_height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("settings.general.notch_match_display_height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("settings.general.notch_custom_height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                        case .matchMenuBar:
                            nonNotchHeight = 24
                        case .matchRealNotchSize:
                            nonNotchHeight = 32
                        case .custom:
                            nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 10...40, step: 1) {
                        Text("settings.general.custom_notch_size \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("settings.general.header.notch_height")
            }
            
            NotchBehaviour()
            
            gestureControls()
        }
        .tint(Defaults[.accentColor])
        .toolbar {
            Button("common.quit_app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .navigationTitle("settings.tab.general")
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }
    
    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(
                NSLocalizedString("settings.general.gestures.enable", comment: "Toggle in parameters to enable gestures"),
                key: .enableGestures
            )
                .disabled(!openNotchOnHover)
            if enableGestures {
                Toggle("settings.general.gestures.media_change_horizontal", isOn: .constant(false))
                    .disabled(true)
                Defaults.Toggle(
                    NSLocalizedString("settings.general.gestures.close", comment: "Toggle in parameters to enable the closing gesture" ),
                    key: .closeGestureEnabled
                )
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("settings.general.gestures.sensitivity")
                        Spacer()
                        Text(Defaults[.gestureSensitivity] == 100 ? "settings.general.gestures.sensitivity.high" : Defaults[.gestureSensitivity] == 200 ? "settings.general.gestures.sensitivity.medium" : "settings.general.gestures.sensitivity.low")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("settings.general.header.gestures")
                customBadge(text: NSLocalizedString("common.beta", comment: "Beta badge"))
            }
        } footer: {
            Text("settings.general.gestures.descriptions.open_close")
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
    
    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(
                NSLocalizedString("settings.general.behavior.enable_haptics", comment: "Parameter toggle for enabling haptics"),
                key: .enableHaptics
            )
            Defaults.Toggle(
                NSLocalizedString("settings.general.behavior.open_on_hover", comment: "Parameter toggle for opening notch on hover"),
                key: .openNotchOnHover
            )
            Toggle("settings.general.behavior.remember_last_tab", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("settings.general.behavior.hover_minimum_duration")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("settings.general.header.behavior")
        }
    }
}

struct Charge: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(
                    NSLocalizedString("settings.battery.show_charging_indicator", comment: "Toogle in parameters to Show charging indicator"),
                    key: .chargingInfoAllowed
                )
                Defaults.Toggle(
                    NSLocalizedString("settings.battery.show_battery_indicator", comment: "Toggle in parameters to show battery indicator"),
                    key: .showBattery
                )
            } header: {
                Text("settings.battery.header.general")
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("settings.tab.battery")
    }
}

struct Downloads: View {
    @Default(.selectedDownloadIndicatorStyle) var selectedDownloadIndicatorStyle
    @Default(.selectedDownloadIconStyle) var selectedDownloadIconStyle
    var body: some View {
        Form {
            warningBadge("We don't support downloads yet", "It will be supported later on.")
            Section {
                Defaults.Toggle(
                    NSLocalizedString("settings.downloads.show_progress", comment: "Toggle in parameters to show the download progress in supported apps"),
                    key: .enableDownloadListener
                )
                    .disabled(true)
                Defaults.Toggle(
                    NSLocalizedString("settings.downloads.enable_safari_dl", comment: "Toggle to in parameters to enable Safari downloads"),
                    key: .enableSafariDownloads
                )
                    .disabled(!Defaults[.enableDownloadListener])
                Picker("settings.downloads.indicator_style", selection: $selectedDownloadIndicatorStyle) {
                    Text("settings.downloads.style.progress_bar")
                        .tag(DownloadIndicatorStyle.progress)
                    Text("settings.downloads.style.percentage")
                        .tag(DownloadIndicatorStyle.percentage)
                }
                Picker("settings.downloads.icon_style", selection: $selectedDownloadIconStyle) {
                    Text("settings.downloads.style.app_icon_only")
                        .tag(DownloadIconStyle.onlyAppIcon)
                    Text("settings.downloads.style.icon_only")
                        .tag(DownloadIconStyle.onlyIcon)
                    Text("settings.downloads.style.both_app_icon")
                        .tag(DownloadIconStyle.iconAndAppIcon)
                }
                
            } header: {
                HStack {
                    Text("settings.downloads.header.indicators")
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
                        Text("settings.downloads.no_excluded_apps")
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
                    Text("settings.downloaders.header.excluded_apps")
                    comingSoonTag()
                }
                
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("settings.tab.downloads")
    }
}

struct HUD: View {
    @EnvironmentObject var vm: BoringViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    var body: some View {
        Form {
            Section {
                Toggle("settings.hud.enable_replacement", isOn: $coordinator.hudReplacement)
            } header: {
                Text("settings.hud.header.general")
            }
            Section {
                Picker("settings.hud.style", selection: $inlineHUD) {
                    Text("common.default")
                        .tag(false)
                    Text("common.inline")
                        .tag(true)
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }
                Picker("settings.hud.progressbar_style", selection: $enableGradient) {
                    Text("common.hierarchical")
                        .tag(false)
                    Text("common.gradient")
                        .tag(true)
                }
                Defaults.Toggle(
                    NSLocalizedString("settings.hud.progressbar_style.enable_glowing", comment: "Toggle in parameters to enable the glowing effet for progress bars"),
                    key: .systemEventIndicatorShadow
                )
                Defaults.Toggle(
                    NSLocalizedString("settings.hud.progressbar_style.use_accent_color", comment: "Toggle in parameters to show the accent color of progress bars"),
                    key: .systemEventIndicatorUseAccent)
            } header: {
                HStack {
                    Text("settings.hud.header.appearance")
                }
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("settings.tab.huds")
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    var body: some View {
        Form {
            Section {
                Toggle(
                    "settings.media.enable_live_activity",
                    isOn: $coordinator.showMusicLiveActivityOnClosed.animation()
                )
                Defaults.Toggle(
                    NSLocalizedString("settings.media.enable_sneak_peek", comment: "Toggle in parameters to enable the Sneak Peek feature"),
                    key: .enableSneakPeek
                )
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("settings.media.timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("settings.media.header.live_activity")
            }
            
            Section {
                Defaults.Toggle(
                    NSLocalizedString("settings.media.autohide_in_fullscreen", comment: "Toggle in the parameters to autohide Boring notch in fullscreen"),
                    key: .enableFullscreenMediaDetection
                )
            } header: {
                HStack {
                    Text("settings.media.header.fullscreen")
                    customBadge(text: NSLocalizedString("common.beta", comment: "Beta badge"))
                }
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("settings.tab.media")
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
                        Text("settings.about.release_name")
                        Spacer()
                        Text(Defaults[.releaseName])
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("settings.about.version")
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
                    Text("settings.about.header.version")
                }
                
                UpdaterSettingsView(updater: updaterController.updater)
                
                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(sponsorPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "cup.and.saucer.fill")
                                .imageScale(.large)
                            Text("settings.about.support_us")
                                .foregroundStyle(.white)
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(productPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                            Text("GitHub")
                                .foregroundStyle(.white)
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
            }
            VStack(spacing: 0) {
                Divider()
                Text("settings.about.footer")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .toolbar {
            Button("settings.toolbar.onboarding") {
                openWindow(id: "onboarding")
            }
            .controlSize(.extraLarge)
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("settings.tab.about")
    }
}

struct Shelf: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(
                    NSLocalizedString("settings.shelf.enable_shelf", comment: "Toggle in parameters to enable shelf system"),
                    key: .boringShelf
                )
                Defaults.Toggle(
                    NSLocalizedString("settings.shelf.open_when_items_added", comment: "Toggle in parameters to open shelf by default if items are added"),
                    key: .openShelfByDefault
                )
            } header: {
                HStack {
                    Text("settings.shelf.header.general")
                }
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("settings.tab.shelf")
    }
}

struct Extensions: View {
    @EnvironmentObject var extensionManager: BoringExtensionManager
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
                                Text("setting.extensions.extension_description")
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
                                Text(isExtensionRunning(item.bundleIdentifier) ? "settings.extensions.running" : item.status == .disabled ? "setting.extensions.disabled" : "settings.extensions.stopped")
                                    .contentTransition(.numericText())
                                    .foregroundStyle(.secondary)
                                    .font(.footnote)
                            }
                            .frame(width: 60, alignment: .leading)
                            
                            Menu(content: {
                                Button("settings.extensions.restart") {
                                    let ws = NSWorkspace.shared
                                    
                                    if let ext = ws.runningApplications.first(where: {$0.bundleIdentifier == item.bundleIdentifier}) {
                                        ext.terminate()
                                    }
                                    
                                    if let appURL = ws.urlForApplication(withBundleIdentifier: item.bundleIdentifier) {
                                        ws.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
                                    }
                                }
                                .keyboardShortcut("R", modifiers: .command)
                                Button("settings.extensions.disable") {
                                    if let ext = NSWorkspace.shared.runningApplications.first(where: {$0.bundleIdentifier == item.bundleIdentifier}) {
                                        ext.terminate()
                                    }
                                    extensionManager.installedExtensions[index].status = .disabled
                                }
                                .keyboardShortcut("D", modifiers: .command)
                                Divider()
                                Button("settings.extensions.uninstall", role: .destructive) {
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
                            Text("settings.extensions.add_manually")
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
                        Text("settings.extensions.no_extensions_installed")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
            } header: {
                HStack(spacing: 0) {
                    Text("settings.extensions.header.installed_extensions")
                    if !extensionManager.installedExtensions.isEmpty {
                        Text(" – \(extensionManager.installedExtensions.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("settings.tab.extensions")
        //TipsView()
        //.padding(.horizontal, 19)
    }
}

struct Appearance: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.sliderColor) var sliderColor
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer
    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"
    @State private var selectedListVisualizer: CustomVisualizer? = nil
    
    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0
    var body: some View {
        Form {
            Section {
                Toggle("settings.appearance.always_show_tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(
                    NSLocalizedString("settings.appearance.settings_icon_in_notch", comment: "Toggle in parameters for settings icon in notch"),
                    key: .settingsIconInNotch
                )
                Defaults.Toggle(
                    NSLocalizedString("settings.appearance.enable_window_shadow", comment: "Toggle in parameters for enabling the window shadow"),
                    key: .enableShadow
                )
                Defaults.Toggle(
                    NSLocalizedString("settings.appearance.corner_radius_scaling", comment: "Toggle in parameters for corner radius scaling"),
                    key: .cornerRadiusScaling
                )
            } header: {
                Text("settings.appearance.header.general")
            }
            
            Section {
                Defaults.Toggle(
                    NSLocalizedString("settings.appearance.enable_colored_spectrograms", comment: "Toggle in parameters for colored spectrograms"),
                    key: .coloredSpectrogram
                )
                Defaults.Toggle(
                    NSLocalizedString("settings.appearance.player_tinting", comment: "Toggle in parameters to tint the player"),
                    key: .playerColorTinting
                )
                Defaults.Toggle(
                    NSLocalizedString("settings.appearance.enable_blur_effect_album_art", comment: "Toggle in parameters to enable the blur effect behind album art"),
                    key: .lightingEffect
                )
                Picker("settings.appearence.media.slider_color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.localizedName)
                    }
                }
            } header: {
                Text("settings.appearance.header.media")
            }
            
            Section {
                Toggle(
                    "settings.appearance.use_music_visualizer_spectrogram",
                    isOn: $useMusicVisualizer.animation()
                )
                .disabled(true)
                if !useMusicVisualizer {
                    if customVisualizers.count > 0 {
                        Picker(
                            "settings.appearance.spectrogram_selected_animation",
                            selection: $selectedVisualizer
                        ) {
                            ForEach(
                                customVisualizers,
                                id: \.self
                            ) { visualizer in
                                Text(visualizer.name)
                                    .tag(visualizer)
                            }
                        }
                    } else {
                        HStack {
                            Text("settings.appearance.spectrogram_selected_animation")
                            Spacer()
                            Text("settings.appearance.spectrogram_selected_animation_none")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("settings.appearance.header.custom_live_activity_anim")
                    customBadge(text: NSLocalizedString("common.coming_soon", comment: "Coming soon badge"))
                }
            }
            
            Section {
                List {
                    ForEach(customVisualizers, id: \.self) { visualizer in
                        HStack {
                            LottieView(state: LUStateData(type: .loadedFrom(visualizer.url), speed: visualizer.speed, loopMode: .loop))
                                .frame(width: 30, height: 30, alignment: .center)
                            Text(visualizer.name)
                            Spacer(minLength: 0)
                            if selectedVisualizer == visualizer {
                                Text("common.selected")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                        .background(
                            selectedListVisualizer != nil ? selectedListVisualizer == visualizer ? Defaults[.accentColor] : Color.clear : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedListVisualizer == visualizer {
                                selectedListVisualizer = nil
                                return
                            }
                            selectedListVisualizer = visualizer
                        }
                    }
                }
                .safeAreaPadding(
                    EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
                )
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 5) {
                        Button {
                            name = ""
                            url = ""
                            speed = 1.0
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        Divider()
                        Button {
                            if selectedListVisualizer != nil {
                                let visualizer = selectedListVisualizer!
                                selectedListVisualizer = nil
                                customVisualizers.remove(at: customVisualizers.firstIndex(of: visualizer)!)
                                if visualizer == selectedVisualizer && customVisualizers.count > 0 {
                                    selectedVisualizer = customVisualizers[0]
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if customVisualizers.isEmpty {
                        Text("settings.appearance.no_custom_visualizer")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading) {
                        Text("settings.appearance.add_custom_visualizer")
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        TextField("common.name", text: $name)
                        TextField("settings.appearance.lottie_json_url", text: $url)
                        HStack {
                            Text("common.speed")
                            Spacer(minLength: 80)
                            Text("\(speed, specifier: "%.1f")s")
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            Slider(value: $speed, in: 0...2, step: 0.1)
                        }
                        .padding(.vertical)
                        HStack {
                            Button {
                                isPresented.toggle()
                            } label: {
                                Text("common.cancel")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            
                            Button {
                                let visualizer: CustomVisualizer = .init(
                                    UUID: UUID(),
                                    name: name,
                                    url: URL(string: url)!,
                                    speed: speed
                                )
                                
                                if !customVisualizers.contains(visualizer) {
                                    customVisualizers.append(visualizer)
                                }
                                
                                isPresented.toggle()
                            } label: {
                                Text("common.add")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .controlSize(.extraLarge)
                    .padding()
                }
            } header: {
                HStack(spacing: 0) {
                    Text("settings.appearance.header.custom_visualizers")
                    if !Defaults[.customVisualizers].isEmpty {
                        Text(" – \(Defaults[.customVisualizers].count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section {
                Defaults.Toggle(
                    NSLocalizedString("settings.appearance.enable_boring_mirror", comment: "Toggle in parameters to enable Boring mirror"),
                    key: .showMirror
                )
                    .disabled(!checkVideoInput())
                Picker("settings.appearance.mirror_shape", selection: $mirrorShape) {
                    Text("settings.appearance.mirror_shape.circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("settings.appearance.mirror_shape.square")
                        .tag(MirrorShapeEnum.rectangle)
                }
                Defaults.Toggle(
                    NSLocalizedString("settings.appearance.show_calendar", comment: "Toggle in parameters to show the calendar in the expanded view"),
                    key: .showCalendar
                )
                Defaults.Toggle(
                    NSLocalizedString("settings.appearance.show_idle_face_animation", comment: "Toggle in parameters to show a face animation when inactive"),
                    key: .showNotHumanFace
                )
                    .disabled(true)
            } header: {
                HStack {
                    Text("settings.appearance.header.additional_features")
                }
            }
            
            Section {
                HStack {
                    ForEach(icons, id: \.self) { icon in
                        Spacer()
                        VStack {
                            Image(icon)
                                .resizable()
                                .frame(width: 80, height: 80)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .circular)
                                        .strokeBorder(
                                            icon == selectedIcon ? Defaults[.accentColor] : .clear,
                                            lineWidth: 2.5
                                        )
                                )
                            
                            Text("common.default")
                                .fontWeight(.medium)
                                .font(.caption)
                                .foregroundStyle(icon == selectedIcon ? .white : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(icon == selectedIcon ? Defaults[.accentColor] : .clear)
                                )
                        }
                        .onTapGesture {
                            withAnimation {
                                selectedIcon = icon
                            }
                            NSApp.applicationIconImage = NSImage(named: icon)
                        }
                        Spacer()
                    }
                }
                .disabled(true)
            } header: {
                HStack {
                    Text("settings.appearance.header.app_icon")
                    customBadge(text: NSLocalizedString("common.coming_soon", comment: "Coming soon badge"))
                }
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("settings.tab.appearance")
    }
    
    func checkVideoInput() -> Bool {
        if let _ = AVCaptureDevice.default(for: .video) {
            return true
        }
        
        return false
    }
}

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("settings.shortcuts.toggle_sneak_peek", name: .toggleSneakPeek)
            } header: {
                Text("settings.shortcuts.header.media")
            } footer: {
                Text("settings.shortcuts.sneak_peek_description")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("settings.shortcuts.toggle_notch", name: .toggleNotchOpen)
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("settings.tab.shortcuts")
    }
}

func proFeatureBadge() -> some View {
    Text("common.upgrade_pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("common.coming_soon")
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
