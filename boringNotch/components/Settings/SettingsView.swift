//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AVFoundation
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import LottieUI
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var extensionManager = BoringExtensionManager()
    let updaterController: SPUStandardUpdaterController
    @StateObject private var calendarManager = CalendarManager()
    
    @State private var selectedTab = "General"
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(destination: GeneralSettings()) {
                    Label("General", systemImage: "gear")
                }
                NavigationLink(destination: Appearance()) {
                    Label("Appearance", systemImage: "eye")
                }
                NavigationLink(destination: Media()) {
                    Label("Media", systemImage: "play.laptopcomputer")
                }
                NavigationLink(destination: CalendarSettings()) {
                    Label("Calendar", systemImage: "calendar")
                }
                if extensionManager.installedExtensions
                    .contains(
                        where: { $0.bundleIdentifier == hudExtension
                        })
                {
                    NavigationLink(destination: HUD()) {
                        Label("HUDs", systemImage: "dial.medium.fill")
                    }
                }
                NavigationLink(destination: Charge()) {
                    Label("Battery", systemImage: "battery.100.bolt")
                }
                if extensionManager.installedExtensions
                    .contains(
                        where: { $0.bundleIdentifier == downloadManagerExtension
                        })
                {
                    NavigationLink(destination: Downloads()) {
                        Label("Downloads", systemImage: "square.and.arrow.down")
                    }
                }
                NavigationLink(destination: Shelf()) {
                    Label("Shelf", systemImage: "books.vertical")
                }
                NavigationLink(destination: Shortcuts()) {
                    Label("Shortcuts", systemImage: "keyboard")
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
        }
        .environmentObject(extensionManager)
        .environmentObject(calendarManager)
        .formStyle(.grouped)
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.keyWindow?.makeKeyAndOrderFront(nil)
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
    @State private var screens: [String] = NSScreen.screens.compactMap { $0.localizedName }
    let accentColors: [Color] = [.blue, .purple, .pink, .red, .orange, .yellow, .green, .gray]
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.accentColor) var accentColor
    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.alwaysHideInFullscreen) var alwaysHideInFullscreen
    
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
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                Picker("Show on a specific display", selection: $coordinator.preferredScreen) {
                    ForEach(screens, id: \.self) { screen in
                        Text(screen)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens =  NSScreen.screens.compactMap({$0.localizedName})
                }
                .disabled(showOnAllDisplays)
                Defaults.Toggle("Automatically switch displays", key: .automaticallySwitchDisplay)
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
            } header: {
                Text("System features")
            }
            
            Section {
                Picker(selection: $notchHeightMode, label:
                    Text("Notch display height")) {
                        Text("Match real notch size")
                            .tag(WindowHeightMode.matchRealNotchSize)
                        Text("Match menubar height")
                            .tag(WindowHeightMode.matchMenuBar)
                        Text("Custom height")
                            .tag(WindowHeightMode.custom)
                    }
                    .onChange(of: notchHeightMode) {
                        switch notchHeightMode {
                        case .matchRealNotchSize:
                            notchHeight = 38
                        case .matchMenuBar:
                            notchHeight = 44
                        case .custom:
                            notchHeight = 38
                        }
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("Custom notch size - \(notchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("Non-notch display height", selection: $nonNotchHeightMode) {
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch size")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom height")
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
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text("Custom notch size - \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("Notch Height")
            }
            
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
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }
    
    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle("Enable gestures", key: .enableGestures)
                .disabled(!openNotchOnHover)
            if enableGestures {
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
        } footer: {
            Text("Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled")
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
    
    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
			Defaults.Toggle("Extend hover area", key: .extendHoverArea)
            Defaults.Toggle("Enable haptics", key: .enableHaptics)
            Defaults.Toggle("Open notch on hover", key: .openNotchOnHover)
            Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Minimum hover duration")
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
            Text("Notch behavior")
        }
    }
}

struct Charge: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle("Show battery indicator", key: .showBatteryIndicator)
                Defaults.Toggle("Show power status notifications", key: .showPowerStatusNotifications)
            } header: {
                Text("General")
            }
            Section {
                Defaults.Toggle("Show battery percentage", key: .showBatteryPercentage)
                Defaults.Toggle("Show power status icons", key: .showPowerStatusIcons)
            } header: {
                Text("Battery Information")
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
                        Button {} label: {
                            Image(systemName: "plus")
                                .frame(width: 25, height: 16, alignment: .center)
                                .contentShape(Rectangle())
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                        Button {} label: {
                            Image(systemName: "minus")
                                .frame(width: 20, height: 16, alignment: .center)
                                .contentShape(Rectangle())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack(spacing: 4) {
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
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    var body: some View {
        Form {
            Section {
                Toggle("Enable HUD replacement", isOn: $coordinator.hudReplacement)
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
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
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
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles
    
    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.rawValue).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("Media Source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("YouTube Music requires this third-party app to be installed: ")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link("https://github.com/th-ch/youtube-music", destination: URL(string: "https://github.com/th-ch/youtube-music")!)
                            .font(.caption)
                            .foregroundColor(.blue) // Ensures it's visibly a link
                    }
                } else {
                    Text("'Now Playing' was the only option on previous versions and works with all media apps.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            Section {
                Toggle(
                    "Enable music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle("Enable sneak peek", isOn: $enableSneakPeek)
                Picker("Sneak Peek Style", selection: $sneakPeekStyles){
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }.disabled(!enableSneakPeek)
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

            Picker(selection: $hideNotchOption, label:
                HStack {
                    Text("Hide BoringNotch Options")
                    customBadge(text: "Beta")
                }) {
                    Text("Always hide in fullscreen").tag(HideNotchOption.always)
                    Text("Hide only when NowPlaying app is in fullscreen").tag(HideNotchOption.nowPlayingOnly)
                    Text("Never hide").tag(HideNotchOption.never)
                }
                .onChange(of: hideNotchOption) { _, newValue in
                    Defaults[.alwaysHideInFullscreen] = newValue == .always
                    Defaults[.enableFullscreenMediaDetection] = newValue != .never
                }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("Media")
    }
    
    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager()
    @Default(.showCalendar) var showCalendar: Bool

    var body: some View {
        Form {
            if calendarManager.authorizationStatus != .fullAccess {
                Text("Calendar access is denied. Please enable it in System Settings.")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
                Button("Open System Settings") {
                    if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(settingsURL)
                    }
                }
            } else {
                Toggle("Show calendar", isOn: $showCalendar)
                Section(header: Text("Select Calendars")) {
                    List {
                        ForEach(calendarManager.allCalendars, id: \.calendarIdentifier) { calendar in
                            Toggle(isOn: Binding(
                                get: { calendarManager.getCalendarSelected(calendar) },
                                set: { isSelected in
                                    calendarManager.setCalendarSelected(calendar, isSelected: isSelected)
                                }
                            )) {
                                Text(calendar.title)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            calendarManager.checkCalendarAuthorization()
        }
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
                        if showBuildNumber {
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
                
                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(sponsorPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "cup.and.saucer.fill")
                                .imageScale(.large)
                            Text("Support Us")
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
                Text("Made with 🫶🏻 by not so boring not.people")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .toolbar {
            Button("Welcome window") {
                openWindow(id: "onboarding")
            }
            .controlSize(.extraLarge)
            CheckForUpdatesView(updater: updaterController.updater)
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
    @EnvironmentObject var extensionManager: BoringExtensionManager
    @State private var effectTrigger: Bool = false
    var body: some View {
        Form {
            //warningBadge("We don't support extensions yet") // Uhhhh You do? <><><> Oori.S
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
                                    
                                    if let ext = ws.runningApplications.first(where: { $0.bundleIdentifier == item.bundleIdentifier }) {
                                        ext.terminate()
                                    }
                                    
                                    if let appURL = ws.urlForApplication(withBundleIdentifier: item.bundleIdentifier) {
                                        ws.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
                                    }
                                }
                                .keyboardShortcut("R", modifiers: .command)
                                Button("Disable") {
                                    if let ext = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == item.bundleIdentifier }) {
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
                    Button {} label: {
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
        // TipsView()
        // .padding(.horizontal, 19)
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
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle("Settings icon in notch", key: .settingsIconInNotch)
                Defaults.Toggle("Enable window shadow", key: .enableShadow)
                Defaults.Toggle("Corner radius scaling", key: .cornerRadiusScaling)
                Defaults.Toggle("Use simpler close animation", key: .useModernCloseAnimation)
            } header: {
                Text("General")
            }
            
            Section {
                Defaults.Toggle("Enable colored spectrograms", key: .coloredSpectrogram)
                Defaults
                    .Toggle("Player tinting", key: .playerColorTinting)
                Defaults.Toggle("Enable blur effect behind album art", key: .lightingEffect)
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.rawValue)
                    }
                }
            } header: {
                Text("Media")
            }
            
            Section {
                Toggle(
                    "Use music visualizer spectrogram",
                    isOn: $useMusicVisualizer.animation()
                )
                .disabled(true)
                if !useMusicVisualizer {
                    if customVisualizers.count > 0 {
                        Picker(
                            "Selected animation",
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
                            Text("Selected animation")
                            Spacer()
                            Text("No custom animation available")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Custom music live activity animation")
                    customBadge(text: "Coming soon")
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
                                Text("selected")
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
                        Text("No custom visualizer")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading) {
                        Text("Add new visualizer")
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        TextField("Name", text: $name)
                        TextField("Lottie JSON URL", text: $url)
                        HStack {
                            Text("Speed")
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
                                Text("Cancel")
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
                                Text("Add")
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
                    Text("Custom vizualizers (Lottie)")
                    if !Defaults[.customVisualizers].isEmpty {
                        Text(" – \(Defaults[.customVisualizers].count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section {
                Defaults.Toggle("Enable boring mirror", key: .showMirror)
                    .disabled(!checkVideoInput())
                Picker("Mirror shape", selection: $mirrorShape) {
                    Text("Circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("Square")
                        .tag(MirrorShapeEnum.rectangle)
                }
                Defaults.Toggle("Show cool face animation while inactivity", key: .showNotHumanFace)
            } header: {
                HStack {
                    Text("Additional features")
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
                            
                            Text("Default")
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
                    Text("App icon")
                    customBadge(text: "Coming soon")
                }
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("Appearance")
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
                KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
            } header: {
                Text("Media")
            } footer: {
                Text("Sneak Peek shows the media title and artist under the notch for a few seconds.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
            }
        }
        .tint(Defaults[.accentColor])
        .navigationTitle("Shortcuts")
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

#Preview {
    HUD()
}
