//
//  OSDSettingsView.swift
//  boringNotch
//
//  Created by Alexander on 2026-02-07.
//

import SwiftUI
import Defaults

struct OSDSettings: View {
    // Defaults-backed storage
    @Default(.osdReplacement) private var osdReplacementDefault
    @Default(.inlineOSD) private var inlineOSDDefault
    @Default(.enableGradient) private var enableGradientDefault
    @Default(.systemEventIndicatorShadow) private var systemEventIndicatorShadowDefault
    @Default(.systemEventIndicatorUseAccent) private var systemEventIndicatorUseAccentDefault
    @Default(.showOpenNotchOSD) private var showOpenNotchOSDDefault
    @Default(.showOpenNotchOSDPercentage) private var showOpenNotchOSDPercentageDefault
    @Default(.showClosedNotchOSDPercentage) private var showClosedNotchOSDPercentageDefault
    @Default(.optionKeyAction) private var optionKeyActionDefault
    @Default(.osdBrightnessSource) private var osdBrightnessSourceDefault
    @Default(.osdVolumeSource) private var osdVolumeSourceDefault
    @State private var isAccessibilityAuthorized = true

    var body: some View {
        Form {
            Section(header: Text("General")) {
                SettingsRow("Replace System OSD") {
                    Toggle(isOn: $osdReplacementDefault) { EmptyView() }
                }
                if osdReplacementDefault {
                    SettingsRow("Use inline style") {
                        Toggle(isOn: $inlineOSDDefault) { EmptyView() }
                    }
                    .padding(.leading, 12)
                }
            }

            if osdReplacementDefault {
                Section(header: Text("Control Sources"), footer: Text("Select which provider to use for system controls. BetterDisplay and Lunar require their respective apps to be installed and running.")) {
                    SettingsRow("Brightness Source") {
                        Picker("", selection: $osdBrightnessSourceDefault) {
                            ForEach(OSDControlSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if osdBrightnessSourceDefault == .betterDisplay && !BetterDisplayManager.shared.isBetterDisplayAvailable {
                        HelpText("BetterDisplay is not installed or not running")
                    }
                    if osdBrightnessSourceDefault == .lunar && !LunarManager.shared.isLunarAvailable {
                        HelpText("Lunar is not installed or not reachable")
                    }

                    SettingsRow("Volume Source") {
                        Picker("", selection: $osdVolumeSourceDefault) {
                            ForEach(OSDControlSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if osdVolumeSourceDefault == .betterDisplay && !BetterDisplayManager.shared.isBetterDisplayAvailable {
                        HelpText("BetterDisplay is not installed or not running")
                    }
                    if osdVolumeSourceDefault == .lunar && !LunarManager.shared.isLunarAvailable {
                        HelpText("Lunar is not installed or not reachable")
                    }

                    SettingsRow("Keyboard Source", help: "Keyboard brightness currently supports the built-in source only.") {
                        Text(OSDControlSource.builtin.rawValue)
                    }
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

                Section(header: Text("Appearance")) {
                    SettingsRow("Enable gradient") {
                        Toggle(isOn: $enableGradientDefault) { EmptyView() }
                    }
                    SettingsRow("Show shadow") {
                        Toggle(isOn: $systemEventIndicatorShadowDefault) { EmptyView() }
                    }
                    SettingsRow("Use accent color") {
                        Toggle(isOn: $systemEventIndicatorUseAccentDefault) { EmptyView() }
                    }
                }

                Section(header: Text("Visibility")) {
                    SettingsRow("Show in open notch") {
                        Toggle(isOn: $showOpenNotchOSDDefault) { EmptyView() }
                    }
                    if showOpenNotchOSDDefault {
                        SettingsRow("Show percentage (open)", help: "Show numeric percentage when notch is open") {
                            Toggle(isOn: $showOpenNotchOSDPercentageDefault) { EmptyView() }
                        }
                    }
                    SettingsRow("Show percentage (closed)", help: "Show numeric percentage when notch is closed") {
                        Toggle(isOn: $showClosedNotchOSDPercentageDefault) { EmptyView() }
                    }
                }

                Section(header: Text("Interaction")) {
                    SettingsRow("Option (⌥) Key Behavior") {
                        Picker("", selection: $optionKeyActionDefault) {
                            ForEach(OptionKeyAction.allCases) { action in
                                Text(action.rawValue).tag(action)
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

    }
}

#Preview {
    OSDSettings()
        .frame(width: 500, height: 600)
}
