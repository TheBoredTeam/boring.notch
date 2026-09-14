//
//  OSDSettingsView.swift
//  boringNotch
//
//  Created by Alexander on 2026-02-07.
//

import SwiftUI
import Defaults
import CoreGraphics

struct OSDSettings: View {
    // Defaults-backed storage
    @Default(.osdReplacement) private var osdReplacementDefault
    @Default(.showOpenNotchOSD) private var showOpenNotchOSDDefault
    @Default(.optionKeyAction) private var optionKeyActionDefault
    @Default(.osdBrightnessSource) private var osdBrightnessSourceDefault
    @Default(.osdVolumeSource) private var osdVolumeSourceDefault
    @Default(.osdDisplayDuration) private var osdDisplayDuration
    @Default(.osdSoundDuration) private var osdSoundDuration
    @State private var isAccessibilityAuthorized = true
    @State private var menuBarBrightnessSupported = true

    /// How long an OSD stays on screen after the last change.
    private static let durationChoices: [Double] = [1.0, 1.5, 2.0, 3.0, 5.0]

    @ViewBuilder
    private func durationPicker(selection: Binding<Double>) -> some View {
        HStack {
            Text("Duration")
            Spacer()
            Picker("", selection: selection) {
                ForEach(Self.durationChoices, id: \.self) { value in
                    Text(String(format: "%.1fs", value)).tag(value)
                }
            }
            .pickerStyle(.menu)
        }
    }

    var body: some View {
        Form {
            Section(header: Text("General")) {
                Defaults.Toggle(key: .osdReplacement) {
                    Text("Replace System OSD")
                }
                if osdReplacementDefault {
                    Defaults.Toggle(key: .inlineOSD) {
                        Text("Use inline style")
                    }
                }
            }

            if osdReplacementDefault {
                Section(header: Text("Control Sources"), footer: Text("Select which provider to use for system controls. BetterDisplay and Lunar require their respective apps to be installed and running.")) {
                    HStack {
                        Text("Brightness Source")
                        Spacer()
                        Picker("", selection: $osdBrightnessSourceDefault) {
                            ForEach(OSDControlSource.allCases) { source in
                                Text(source.localizedString).tag(source)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if osdBrightnessSourceDefault == .builtin {
                        HelpText("Only Apple displays are supported. In multi-display setups, the brightness OSD appears on the active display if supported, or on another supported display otherwise.")
                    }
                    if osdBrightnessSourceDefault == .betterDisplay && !BetterDisplayManager.shared.isBetterDisplayAvailable {
                        HelpText("BetterDisplay is not installed or not running")
                    }
                    if osdBrightnessSourceDefault == .lunar && !LunarManager.shared.isLunarAvailable {
                        HelpText("Lunar is not installed or not reachable")
                    }

                    HStack {
                        Text("Volume Source")
                        Spacer()
                        Picker("", selection: $osdVolumeSourceDefault) {
                            // Lunar does not support volume control so hide it from the picker
                            ForEach(OSDControlSource.allCases.filter { $0 != .lunar }) { source in
                                Text(source.localizedString).tag(source)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if osdVolumeSourceDefault == .betterDisplay && !BetterDisplayManager.shared.isBetterDisplayAvailable {
                        HelpText("BetterDisplay is not installed or not running")
                    }

                    HStack {
                        Text("Keyboard Source")
                        Spacer()
                        Text(OSDControlSource.builtin.localizedString)
                    }
                    HelpText("Keyboard brightness currently supports the built-in source only.")
                    if !isAccessibilityAuthorized {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "accessibility")
                                .font(.title)
                                .foregroundStyle(Color.effectiveAccent)
                                
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Accessibility Access Required")
                                    .font(.headline)
                                Text("Grant Accessibility access so built-in keyboard brightness controls can be intercepted.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Grant Access") {
                                Task {
                                    let granted = await MediaKeyInterceptor.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                                    await MainActor.run {
                                        isAccessibilityAuthorized = granted
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: Text("Display")) {
                    Defaults.Toggle(key: .osdBrightnessEnabled) {
                        Text("Show brightness OSD")
                    }
                    Defaults.Toggle(key: .osdKeyboardBrightnessEnabled) {
                        Text("Show keyboard brightness OSD")
                    }
                    durationPicker(selection: $osdDisplayDuration)

                    if osdBrightnessSourceDefault == .builtin {
                        Defaults.Toggle(key: .osdObserveExternalBrightness) {
                            Text("Detect brightness changes from elsewhere")
                        }
                        .onChange(of: Defaults[.osdObserveExternalBrightness]) {
                            BrightnessManager.shared.observeExternalChangesIfEnabled()
                        }
                        HelpText("macOS sends no notification when brightness changes, so catching changes made in Control Centre or by auto-brightness requires checking once a second. Off by default. BetterDisplay and Lunar report changes properly, without polling.")
                    }
                }

                Section(header: Text("Sound")) {
                    Defaults.Toggle(key: .osdVolumeEnabled) {
                        Text("Show volume OSD")
                    }
                    durationPicker(selection: $osdSoundDuration)
                    Defaults.Toggle(key: .osdHideLabel) {
                        Text("Hide label")
                    }
                    HelpText("Hides the \u{201C}Volume\u{201D} and \u{201C}Brightness\u{201D} labels in the inline OSD, leaving just the icon and level.")
                }

                Section(header: Text("Appearance")) {
                    Defaults.Toggle(key: .enableGradient) {
                        Text("Enable gradient")
                    }
                    Defaults.Toggle(key: .systemEventIndicatorShadow) {
                        Text("Show shadow")
                    }
                    Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                        Text("Use accent color")
                    }
                    Defaults.Toggle(key: .osdLimitBounce) {
                        Text("Bounce at maximum")
                    }
                }

                Section(header: Text("Visibility")) {
                    Defaults.Toggle(key: .showOpenNotchOSD) {
                        Text("Show OSD in open notch")
                    }
                    if showOpenNotchOSDDefault {
                        Defaults.Toggle(key: .showOpenNotchOSDPercentage) {
                            Text("Show percentage (open notch)")
                        }
                    }
                    Defaults.Toggle(key: .showClosedNotchOSDPercentage) {
                        Text("Show percentage (closed notch)")
                    }
                }

                Section(header: Text("Interaction")) {
                    HStack {
                        Text("Option (⌥) Key Behavior")
                        Spacer()
                        Picker("", selection: $optionKeyActionDefault) {
                            ForEach(OptionKeyAction.allCases) { action in
                                Text(action.localizedString).tag(action)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    HelpText("Define what happens when you hold the Option key while pressing media keys.")
                }
            }

        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
        .task(id: osdReplacementDefault) {
            guard osdReplacementDefault else { return }
            isAccessibilityAuthorized = await MediaKeyInterceptor.shared.ensureAccessibilityAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notif in
            if let granted = notif.userInfo?["granted"] as? Bool {
                isAccessibilityAuthorized = granted
            }
        }
        .task(id: osdBrightnessSourceDefault) {
            if osdBrightnessSourceDefault == .builtin {
                if let displayID = await XPCHelperClient.shared.displayIDForBrightness() {
                    let menuID = NSScreen.main?.cgDisplayID ?? CGMainDisplayID()
                    menuBarBrightnessSupported = (displayID == menuID)
                } else {
                    menuBarBrightnessSupported = false
                }
            } else {
                menuBarBrightnessSupported = true
            }
        }

    }
}

#Preview {
    OSDSettings()
        .frame(width: 500, height: 600)
}
