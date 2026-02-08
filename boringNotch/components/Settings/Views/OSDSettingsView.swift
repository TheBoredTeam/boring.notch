//
//  OSDSettingsView.swift
//  boringNotch
//
//  Created by Alexander on 2026-02-07.
//

import SwiftUI
import Defaults

struct OSDSettings: View {
    @StateObject private var vm = OSDSettingsViewModel()

    var body: some View {
        Form {
            Section(header: Text("General")) {
                SettingsRow("Replace System OSD") {
                    Toggle(isOn: $vm.osdReplacement) { EmptyView() }
                }
                if vm.osdReplacement {
                    SettingsRow("Use inline style") {
                        Toggle(isOn: $vm.inlineOSD) { EmptyView() }
                    }
                    .padding(.leading, 12)
                }
            }

            Section(header: Text("Control Backends"), footer: Text("Select which provider to use for system controls. BetterDisplay and Lunar require their respective apps to be installed and running.")) {
                HStack {
                    Text("Brightness Source")
                    Spacer()
                    Picker("", selection: $vm.osdBrightnessSource) {
                        ForEach(OSDControlSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if vm.osdBrightnessSource == .betterDisplay && !vm.isBetterDisplayAvailable {
                    HelpText("BetterDisplay is not installed or not running")
                }

                HStack {
                    Text("Volume Source")
                    Spacer()
                    Picker("", selection: $vm.osdVolumeSource) {
                        ForEach(OSDControlSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if vm.osdVolumeSource == .betterDisplay && !vm.isBetterDisplayAvailable {
                    HelpText("BetterDisplay is not installed or not running")
                }

                HStack {
                    Text("Keyboard Source")
                    Spacer()
                    Picker("", selection: $vm.osdKeyboardSource) {
                        ForEach(OSDControlSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if vm.osdKeyboardSource == .lunar && !vm.isLunarAvailable {
                    HelpText("Lunar is not installed or not reachable")
                }
            }

            Section(header: Text("Appearance")) {
                SettingsRow("Enable gradient") {
                    Toggle(isOn: $vm.enableGradient) { EmptyView() }
                }
                SettingsRow("Show shadow") {
                    Toggle(isOn: $vm.systemEventIndicatorShadow) { EmptyView() }
                }
                SettingsRow("Use accent color") {
                    Toggle(isOn: $vm.systemEventIndicatorUseAccent) { EmptyView() }
                }
            }

            Section(header: Text("Visibility")) {
                SettingsRow("Show in open notch") {
                    Toggle(isOn: $vm.showOpenNotchOSD) { EmptyView() }
                }
                if vm.showOpenNotchOSD {
                    SettingsRow("Show percentage (open)", help: "Show numeric percentage when notch is open") {
                        Toggle(isOn: $vm.showOpenNotchOSDPercentage) { EmptyView() }
                    }
                }
                SettingsRow("Show percentage (closed)", help: "Show numeric percentage when notch is closed") {
                    Toggle(isOn: $vm.showClosedNotchOSDPercentage) { EmptyView() }
                }
            }

            Section(header: Text("Interaction")) {
                HStack {
                    Text("Option (⌥) Key Behavior")
                    Spacer()
                    Picker("", selection: $vm.optionKeyAction) {
                        ForEach(OptionKeyAction.allCases) { action in
                            Text(action.rawValue).tag(action)
                        }
                    }
                    .pickerStyle(.menu)
                }
                HelpText("Define what happens when you hold the Option key while pressing media keys.")
            }

        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)

    }
}

#Preview {
    OSDSettings()
        .frame(width: 500, height: 600)
}
